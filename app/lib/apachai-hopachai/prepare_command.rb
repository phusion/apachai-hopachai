# encoding: utf-8
require_relative 'command_utils'

module ApachaiHopachai
  class PrepareCommand < Command
    include CommandUtils

    COMBINATORIC_KEYS = ['rvm', 'gemfile', 'env'].freeze

    def self.description
      "Prepare test jobs"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def initialize(*args)
      super(*args)
    end

    def start
      require_libs
      parse_argv
      maybe_set_log_file
      maybe_daemonize
      maybe_create_pid_file
      begin
        create_work_dir
        begin
          prepare_job_set
          clone_repo
          extract_repo_info
          load_travis_yml
          environments = calculate_build_matrix
          create_job_set(environments)
        ensure
          destroy_work_dir
        end
      ensure
        maybe_destroy_pid_file
      end
    end

    private

    def require_libs
      require 'tmpdir'
      require 'fileutils'
      require 'shellwords'
      require_relative 'safe_yaml'
      require_relative 'database_models'
    end

    def option_parser
      require 'optparse'
      @options = {}
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa prepare [OPTIONS] OWNER/PROJECT_NAME [COMMIT]"
        opts.separator "Prepare running test jobs on the given git repository."
        opts.separator ""

        opts.separator "Options:"
        opts.on("--limit N", Integer, "Limit the number of environments to prepare. Default: prepare all environments") do |val|
          @options[:limit] = val
        end
        opts.on("--before-sha SHA", String, "The SHA of the beginning of the changeset, to display in reports") do |val|
          @options[:before_sha] = val
        end
        opts.on("--travis-yml FILENAME", String, "Use the given .travis.yml instead of the one in the repository") do |val|
          @options[:travis_yml] = val
        end
        opts.on("--id-file FILENAME", String, "Write the job set ID to the given file") do |val|
          @options[:id_file] = val
        end
        opts.on("--daemonize", "-d", "Daemonize into background") do
          @options[:daemonize] = true
        end
        opts.on("--pid-file FILENAME", String, "Write PID to this file") do |val|
          @options[:pid_file] = val
        end
        opts.on("--log-file FILENAME", "-l", String, "Log to the given file") do |val|
          @options[:log_file] = val
        end
        opts.on("--log-level LEVEL", String, "Set log level. One of: fatal,error,warn,info,debug") do |val|
          set_log_level(val)
        end
        opts.on("--help", "-h", "Show help message") do
          @options[:help] = true
        end
      end
    end

    def parse_argv
      begin
        option_parser.parse!(@argv)
      rescue OptionParser::ParseError => e
        STDERR.puts e
        STDERR.puts
        STDERR.puts "Please see 'appa help prepare' for valid options."
        exit 1
      end

      if @options[:help]
        self.class.help
        exit 0
      end
      if @argv.size < 1 || @argv.size > 2
        self.class.help
        exit 1
      end
      if @options[:daemonize] && !@options[:log_file]
        abort "If you set --daemonize then you must also set --log-file."
      end

      @project = Project.find_by_long_name(@argv[0])
      if !@project
        abort "Could not find a project with owner and name #{argv[0].inspect}."
      end
      @options[:commit] = @argv[1]
    end

    def create_work_dir
      @work_dir = Dir.mktmpdir("appa-")
    end

    def destroy_work_dir
      FileUtils.remove_entry_secure(@work_dir)
    end

    def prepare_job_set
      @job_set = JobSet.new
      @job_set.project = @project
      @job_set.before_revision = @options[:before_sha]
    end

    def clone_repo
      if @options[:commit]
        @logger.info "Cloning from #{@project.repo_url}, commit #{@options[:commit]}"
      else
        @logger.info "Cloning from #{@project.repo_url}"
      end

      args = []
      if !@options[:commit]
        args << "--single-branch" if `git clone --help` =~ /--single-branch/
        args << "--depth 1"
      end

      if !system("git clone #{args.join(' ')} #{Shellwords.escape @project.repo_url} #{Shellwords.escape @work_dir}/repo")
        abort "Git clone failed"
      end

      if @options[:commit]
        if !system("git", "checkout", "-q", @options[:commit], :chdir => "#{@work_dir}/repo")
          abort "Unable to checkout commit #{@options[:commit]}"
        end
      end
    end

    def extract_repo_info
      e_dir = Shellwords.escape("#{@work_dir}/repo")
      lines = `cd #{e_dir} && git show --pretty='format:%H\n%an\n%ae\n%cn\n%ce\n%s' -s`.split("\n")
      @job_set.revision,
        @job_set.author_name,
        @job_set.author_email,
        @job_set.committer_name,
        @job_set.committer_email,
        @job_set.subject = lines
    end

    def load_travis_yml
      if @options[:travis_yml]
        filename = @options[:travis_yml]
      else
        filename = "#{@work_dir}/repo/.travis.yml"
      end
      @logger.debug("Loading Travis project configuration from #{filename}")
      @travis = YAML.load_file(filename, :safe => true)
    end

    def calculate_build_matrix
      matrix = BuildMatrix.new(@travis)
      matrix.calculate
      environments = matrix.environments
      if @logger.debug?
        @logger.debug("Calculated build matrix:")
        environments.each_with_index do |env, i|
          @logger.debug("  ##{i} -> #{env.inspect}")
        end
      end

      if @options[:limit]
        @logger.info "Limiting to #{@options[:limit]} environment(s)."
        environments = environments.slice(0, @options[:limit])
      end

      environments
    end

    def create_job_set(environments)
      @job_set.set_properties_from_travis_config(@travis)

      environments.each_with_index do |environment, i|
        create_job(@job_set, environment, i + 1)
      end

      if @job_set.save
        @logger.info("Created job set with ID #{@job_set.id}. " +
          "It contains #{@job_set.jobs.count} jobs, with IDs #{@job_set.job_ids}")
        create_id_file
        @logger.info("Creating repo cache...")
        if create_job_set_repo_cache
          @logger.info("Repo cache created.")
        else
          @logger.warn("Unable to create repository cache file for job set.")
        end
      else
        @logger.error "Could not create job set:"
        report_model_errors(@logger, @job_set)
        abort
      end
    end

    def create_id_file
      if path = @options[:id_file]
        File.open(path, "w") do |f|
          f.write(@job_set.id.to_s)
        end
      end
    end

    def create_job_set_repo_cache
      @logger.debug "Creating archive #{@job_set.repo_cache_path}"
      parent_dir = File.dirname(@job_set.repo_cache_path)
      if !File.exist?(parent_dir)
        begin
          Dir.mkdir(parent_dir, 0700)
        rescue Errno::EEXIST
        end
      end
      result = system("env", "GZIP=-3", "tar", "-czf",
        "#{@job_set.repo_cache_path}.tmp", ".", :chdir => "#{@work_dir}/repo")
      if result
        File.rename("#{@job_set.repo_cache_path}.tmp", @job_set.repo_cache_path)
      else
        false
      end
    end

    def create_job(job_set, environment, number)
      name = BuildMatrix.environment_display_name(environment)
      @logger.info "Preparing job ##{number}: #{name}"
      job = job_set.jobs.build
      job.number = number
      job.name = name
      job.environment = environment
      if !job.valid?
        @logger.error "Could not create job #{number}:"
        report_model_errors(@logger, job)
        abort
      end
      job
    end
  end
end
