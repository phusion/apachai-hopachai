class Job < ActiveRecord::Base
  class AlreadyProcessing < StandardError; end

  INTERNAL_LOCK_ID = ApachaiHopachai::INTERNAL_LOCK_ID_START

  belongs_to :job_set, :inverse_of => :jobs

  serialize :environment, Hash
  as_enum :state, [:unprocessed, :processing, :succeeded, :failed, :errored],
    :strings => true, :slim => true

  default_value_for :state, :unprocessed

  before_create :create_log_file
  after_destroy :delete_log_file

  validates :state, :as_enum => true
  validates :worker_pid, :presence => true, :if => :state_processing?


  ##### Queries #####

  def owner
    job_set.owner
  end

  def project
    job_set.project
  end

  def long_number
    "#{job_set.number}.#{number}"
  end

  def part_of_latest_build?
    job_set.is_latest_build?
  end

  def processed?
    state == :succeeded || state == :failed || state == :errored
  end

  def status_css_class
    case state
    when :unprocessed, :processing
      "job-unprocessed"
    when :succeeded
      "job-succeeded"
    when :failed
      "job-failed"
    when :errored
      "job-errored"
    end
  end

  def public_environment_string
    env = environment.dup
    env = env.sort do |a, b|
      a[0] <=> b[0]
    end
    env.map! do |item|
      "#{item[0]}=#{item[1]}"
    end
    env.join(" ")
  end

  def running_time
    if state == :processing
      distance_of_time_in_words(Time.now, start_time, :include_seconds => true)
    else
      "-"
    end
  end

  def log_file_path
    if log_file_name
      "#{job_logs_path}/#{log_file_name}"
    else
      nil
    end
  end

  def read_log_file
    File.open(log_file_path, "rb") do |f|
      f.read.force_encoding("utf-8").scrub
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

  # If this job has state :processing, checks whether the worker is still alive.
  # If the worker actually crashed without properly cleaning up the database
  # information, then this method fixes the database information.
  def check_really_processing!
    return :not_processing if state != :processing
    internal_lock do
      if try_lock_job
        begin
          set_state!(:errored, false)
          :stale_worker_detected
        ensure
          unlock_job
        end
      else
        :really_processing
      end
    end
  end

  # Warning: if you use this method from the web UI, ABSOLUTELY MAKE SURE that you
  # call `set_errored!`/`set_succeeded!`/`set_failed!` within the same request.
  # This is because `try_lock_job` will grab a PostgreSQL connection-level advisory
  # lock. But since Rails uses a connection pool, if you don't unlock before the
  # connection is returned to the pool, then you won't be able to unlock it correctly.
  def set_processing!
    locked = false
    internal_lock do
      locked = try_lock_job
    end
    if locked
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
    set_state!(:errored)
  end

  def set_succeeded!
    set_state!(:succeeded)
  end

  def set_failed!
    set_state!(:failed)
  end

private
  def state_processing?
    state == :processing
  end

  def job_logs_path
    storage_path = ApachaiHopachai.config['storage_path']
    "#{storage_path}/job_logs"
  end

  def create_log_file
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
    rescue Exception => e
      delete_file_no_error(log_file_path)
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

  def delete_log_file
    delete_file_no_error(log_file_path)
  end

  # `check_really_processing!` checks whether a worker process is really processing this job,
  # by temporarily grabbing the job lock. During that short time, `set_processing!` might be
  # called. To avoid a failure in those concurrent scenarios, we protect job lock operations
  # with an internal lock.
  def internal_lock
    connection.execute("SELECT pg_advisory_lock(#{INTERNAL_LOCK_ID})")
    begin
      yield
    ensure
      connection.execute("SELECT pg_advisory_unlock(#{INTERNAL_LOCK_ID})")
    end
  end

  def job_lock_id
    ApachaiHopachai::JOB_LOCK_ID_START + id
  end

  # Only use within an `internal_lock` block!
  def try_lock_job
    raise "Job already locked" if owns_job_lock?
    result = connection.select_one("SELECT pg_try_advisory_lock(#{job_lock_id}) AS result")
    if result["result"] == "t"
      @owns_job_lock = true
      true
    else
      false
    end
  end

  # Only use within an `internal_lock` block!
  def unlock_job
    raise "Not already locked" if !owns_job_lock?
    connection.execute("SELECT pg_advisory_unlock(#{job_lock_id})")
    @owns_job_lock = nil
  end

  def owns_job_lock?
    !!@owns_job_lock
  end

  def set_state!(value, do_unlock = true)
    if do_unlock
      unlock_job if owns_job_lock?
    end
    update_attributes!(:state => value,
      :worker_pid => nil,
      :end_time => Time.now)
  end
end
