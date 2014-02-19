class JobSet < ActiveRecord::Base
  SCRIPT_PROPERTIES = [:before_install_script, :install_script, :before_script, :script,
    :after_success_script, :after_failure_script, :after_script].freeze

  has_many :jobs, -> { order(:number) },
    :inverse_of => :job_set, :autosave => true, :dependent => :destroy
  belongs_to :project, :inverse_of => :job_sets

  SCRIPT_PROPERTIES.each { |prop| serialize(prop, Array) }
  as_enum :state, [:unprocessed, :processing, :succeeded, :failed, :errored],
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
    state == :succeeded || state == :failed || state == :errored
  end

  def is_latest_build?
    id == project.job_sets.first.id
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

private
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
end
