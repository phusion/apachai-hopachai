class Job < ActiveRecord::Base
  class AlreadyProcessing < StandardError; end

  belongs_to :job_set, :inverse_of => :jobs

  serialize :environment, Hash
  as_enum :state, [:unprocessed, :processing, :succeeded, :failed, :errored],
    :strings => true, :slim => true

  default_value_for :state, :unprocessed

  before_create :create_log_and_lock_files
  after_destroy :delete_log_and_lock_files

  validates :state, :as_enum => true
  validates :worker_pid, :presence => true, :if => :state_processing?


  ##### Queries #####

  def processed?
    state == :succeeded || state == :failed || state == :errored
  end

  def log_file_path
    if log_file_name
      "#{job_logs_path}/#{log_file_name}"
    else
      nil
    end
  end

  def lock_file_path
    if lock_file_name
      "#{job_logs_path}/#{lock_file_name}"
    else
      nil
    end
  end

  def as_json(options = nil)
    if options.nil? || options.empty?
      options = { :only => [:state, :number, :name, :created_at, :environment] }
    end
    super(options)
  end


  ##### Properties #####

  def environment=(env)
    if !env.is_a?(Hash)
      items = env.to_s.split(/ +/)
      env = {}
      items.each do |item|
        key, value = item.split("=", 2)
        env[key] = value
      end
    end
    env.keys.each do |key|
      value = env[key]
      if !value.is_a?(String)
        env[key] = value.to_s
      end
    end
    super(env)
  end


  #### Commands #####

  def try_lock_job
    raise "Job already locked" if job_locked?
    begin
      @job_lock = File.open(lock_file_path, "r")
      if @job_lock.flock(File::LOCK_EX | File::LOCK_NB)
        true
      else
        @job_lock.close
        @job_lock = nil
        false
      end
    rescue Exception => e
      @job_lock = nil
      raise e
    end
  end

  def unlock_job
    raise "Not already locked" if !job_locked?
    begin
      @job_lock.close
    ensure
      @job_lock = nil
    end
  end

  def job_locked?
    !!@job_lock
  end

  def set_processing!
    if try_lock_job
      if state == :processing
        logger.warn "This job was previously being processed, but it never finished."
      elsif processed?
        logger.warn "This job has already been processed. Rerunning it."
      end
      transaction do
        job_set.update_attributes!(:state => :processing)
        update_attributes!(:state => :processing,
          :worker_pid => Process.pid,
          :start_time => Time.now)
      end
    else
      raise AlreadyProcessing, "Job is already being processed"
    end
  end

  def set_errored!
    unlock_job if job_locked?
    update_attributes!(:state => :errored,
      :worker_pid => nil,
      :end_time => Time.now)
  end

  def set_succeeded!
    unlock_job if job_locked?
    update_attributes!(:state => :succeeded,
      :worker_pid => nil,
      :end_time => Time.now)
  end

  def set_failed!
    unlock_job if job_locked?
    update_attributes!(:state => :failed,
      :worker_pid => nil,
      :end_time => Time.now)
  end

private
  def state_processing?
    state == :processing
  end

  def job_logs_path
    storage_path = ApachaiHopachai.config['storage_path']
    "#{storage_path}/job_logs"
  end

  def create_log_and_lock_files
    storage_path = ApachaiHopachai.config['storage_path']
    job_logs_path = "#{storage_path}/job_logs"
    if !File.exist?(job_logs_path)
      begin
        Dir.mkdir(job_logs_path, 0700)
      rescue Errno::EEXIST
      end
    end

    datetime = Time.now.strftime("%Y%m%d-%H%M")
    self.log_file_name = nil
    self.lock_file_name = nil

    begin
      begin
        name = "#{datetime}-#{rand(0xFFFFFFFF)}.log"
        begin
          File.new("#{job_logs_path}/#{name}", File::WRONLY | File::CREAT | File::EXCL, 0600).close
        rescue Errno::EEXIST
          retry
        end
      end
      self.log_file_name = name

      begin
        name = "#{datetime}-#{rand(0xFFFFFFFF)}.lock"
        begin
          File.new("#{job_logs_path}/#{name}", File::WRONLY | File::CREAT | File::EXCL, 0600).close
        rescue Errno::EEXIST
          retry
        end
      end
      self.lock_file_name = name
    rescue Exception => e
      delete_file_no_error(log_file_path)
      delete_file_no_error(lock_file_path)
      raise e
    end
  end

  def delete_file_no_error(filename)
    if filename
      begin
        File.unlink(filename)
      rescue Errno::ENOENT
      end
    end
  end

  def delete_log_and_lock_files
    delete_file_no_error(log_file_path)
    delete_file_no_error(lock_file_path)
  end
end
