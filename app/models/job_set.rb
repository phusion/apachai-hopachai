class JobSet < ActiveRecord::Base
  SCRIPT_PROPERTIES = [:before_install_script, :install_script, :before_script, :script,
    :after_success_script, :after_failure_script, :after_script].freeze

  has_many :jobs, -> { order(:number) },
    :inverse_of => :job_set, :autosave => true, :dependent => :destroy
  belongs_to :project, :inverse_of => :job_sets

  SCRIPT_PROPERTIES.each { |prop| serialize(prop, Array) }
  as_enum :state, [:unprocessed, :processing, :passed, :failed, :errored],
    :strings => true, :slim => true
  acts_as_list :column => "number", :scope => :project

  default_value_for :state, :unprocessed

  validates :state, :as_enum => true
  validates :revision, :author_name, :author_email, :committer_name, :committer_email, :subject, :presence => true
  validate :scripts_are_string_arrays


  ##### Queries #####

  def owner
    project.owner
  end

  def processed?
    state == :passed || state == :failed || state == :errored
  end

  def is_latest_build?
    id == project.job_sets.first.id
  end

  def short_revision
    revision[0..6]
  end

  def short_before_revision
    if before_revision
      before_revision[0..6]
    else
      nil
    end
  end

  def short_revision_set
    if before_revision
      "#{short_before_revision}..#{short_revision}"
    else
      short_revision
    end
  end

  def human_friendly_end_time
    if finalized_at
      DateHelper.new.time_ago_in_words(finalized_at) + " ago"
    else
      "-"
    end
  end

  def human_friendly_duration
    if finalized_at
      DateHelper.new.distance_of_time_in_words(created_at, finalized_at)
    else
      "-"
    end
  end

  def repo_cache_path
    if new_record?
      nil
    else
      storage_path = ApachaiHopachai.config['storage_path']
      "#{storage_path}/repo_caches/#{id}.tar.gz"
    end
  end

  def as_json(options = nil)
    if options.nil? || options.empty?
      options = { :except => [:id, :project_id, :state_cd] }
    end
    super(options)
  end


  ##### Setters #####

  def set_properties_from_travis_config(travis_config)
    set_property_from_travis_config(travis_config, :language)
    set_property_from_travis_config(travis_config, :bundler_args)
    set_property_from_travis_config(travis_config, :init_git_submodules)
    set_script_property_from_travis_config(travis_config, :before_install_script, :before_install)
    set_script_property_from_travis_config(travis_config, :install_script, :install)
    set_script_property_from_travis_config(travis_config, :before_script, :before_script)
    set_script_property_from_travis_config(travis_config, :script, :script)
    set_script_property_from_travis_config(travis_config, :after_success, :after_success)
    set_script_property_from_travis_config(travis_config, :after_failure, :after_failure)
    set_script_property_from_travis_config(travis_config, :after_script, :after_script)
  end


  ##### Commands #####

  # Begin finalizing this job set. To be called after all jobs have been processed,
  # and to be used in combination with `send_notifications`.
  # 
  # Returns whether this call has changed the job set state to one of the processed
  # states.
  # 
  # You are supposed to call `try_finalize!`, check whether it returns true, and
  # if so call `send_notifications` later when you've **exited the transaction**.
  # 
  #     finalized = nil
  #     transaction do
  #       ...
  #       finalized = job_set.try_finalize!
  #     end
  #     if finalized
  #       job_set.send_notifications
  #     end
  def try_finalize!
    transaction do
      advisory_lock do
        reload
        return false if processed?
        jobs.reload
        if jobs.all? { |job| job.processed? }
          if jobs.all? { |job| job.state == :passed }
            logger.info "Finalizing job set: setting state to 'passed'."
            self.state = :passed
          elsif jobs.all? { |job| job.state == :failed }
            logger.info "Finalizing job set: setting state to 'failed'."
            self.state = :failed
          else
            logger.info "Finalizing job set: setting state to 'errored'."
            self.state = :errored
          end
          self.finalized_at = Time.now
          save!
          true
        else
          false
        end
      end
    end
  end

  # Warning: do not call this within the same transaction as `try_finalize!`!
  # This is because sending notifications is handled asynchronously in a worker.
  # If the worker tries to load the database record before the transaction has
  # been committed, then it may not see the most up to date information.
  def send_notifications
    raise "Job set is not yet fully processed." if !processed?

    logger.info "Scheduling build report email."
    Mailer.delay(:queue => :notifications).build_report(id)
  end

private
  class DateHelper
    include ActionView::Helpers::DateHelper
  end

  def scripts_are_string_arrays
    SCRIPT_PROPERTIES.each do |prop|
      array = send(prop)
      if !array.nil?
        if !array.is_a?(Array)
          add_error(prop, "must be an array")
        else
          array.each do |value|
            if !value.is_a?(String)
              add_error(prop, "must only contain strings")
            end
          end
        end
      end
    end
  end

  def set_and_maybe_nullify(property, value)
    if value.blank?
      self.send("#{property}=", nil)
    else
      self.send("#{property}=", value)
    end
  end

  def set_property_from_travis_config(travis_config, prop)
    prop = prop.to_s
    if travis_config.has_key?(prop)
      value = travis_config[prop]
      set_and_maybe_nullify(prop, value)
    end
  end

  def set_script_property_from_travis_config(travis_config, key, prop)
    if value = travis_config[key.to_s]
      if !value.is_a?(Array)
        value = [value.to_s]
      end
      set_and_maybe_nullify(prop, value)
    end
  end

  def job_set_lock_id
    ApachaiHopachai::JOB_SET_LOCK_ID_START + id
  end

  def advisory_lock
    self.class.connection.execute("SELECT pg_advisory_lock(#{job_set_lock_id})")
    begin
      yield
    ensure
      self.class.connection.execute("SELECT pg_advisory_unlock(#{job_set_lock_id})")
    end
  end
end
