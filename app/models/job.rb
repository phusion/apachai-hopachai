class Job < ActiveRecord::Base
  belongs_to :job_set, :inverse_of => :jobs

  serialize :environment, Hash
  as_enum :state, [:unprocessed, :processing, :succeeded, :failed, :errored], :strings => true, :slim => true

  default_value_for :state, :unprocessed

  after_create :create_log_file

  validates :state, :as_enum => true

  def environment=(value)
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
    super(value)
  end

  def processed?
    state == :succeeded || state == :failed || state == :errored
  end

private
  def create_log_file
    storage_path = ApachaiHopachai.config['storage_path']
    job_logs_path = "#{storage_path}/job_logs"
    if !File.exist?(job_logs_path)
      begin
        Dir.mkdir(job_logs_path, 0700)
      rescue Errno::EEXIST
      end
    end
    path = "#{job_logs_path}/#{id}.log"
    File.open(path, "w").close
    update_attributes!(:log_file_path, path)
  end
end
