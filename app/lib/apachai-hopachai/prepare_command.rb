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
          environments = infer_test_environments
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
      require 'safe_yaml'
      require 'fileutils'
      require 'shellwords'
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

      begin
        @project = Project.find_by_owner_and_name(@argv[0])
      rescue ActiveRecord::RecordNotFound
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
      @job_set.before_revision = result['before_sha']
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

    def infer_test_environments
      config = YAML.load_file("#{@work_dir}/repo/.travis.yml", :safe => true)
      environments = []
      traverse_combinations(0, environments, config, COMBINATORIC_KEYS)
      environments.sort! do |a, b|
        inspect_env(a) <=> inspect_env(b)
      end
      
      @logger.info "Inferred #{environments.size} test environments"
      environments.each do |env|
        @logger.debug "  #{inspect_env(env)}"
      end

      if @options[:limit]
        @logger.info "Limiting to #{@options[:limit]} environments"
        environments = environments.slice(0, @options[:limit])
      end

      environments
    end

    def traverse_combinations(level, environments, current, remaining_combinatoric_keys)
      indent = "  " * level
      @logger.debug "#{indent}traverse_combinations: #{remaining_combinatoric_keys.inspect}"
      remaining_combinatoric_keys = remaining_combinatoric_keys.dup
      key = remaining_combinatoric_keys.shift
      if values = current[key]
        values = [values] if !values.is_a?(Array)
        values.each do |val|
          @logger.debug "#{indent}  val = #{val.inspect}"
          current = current.dup
          current[key] = val
          if remaining_combinatoric_keys.empty?
            @logger.debug "#{indent}  Inferred environment: #{inspect_env(current)}"
            environments << current
          else
            traverse_combinations(level + 1, environments, current, remaining_combinatoric_keys)
          end
        end
      elsif !remaining_combinatoric_keys.empty?
        traverse_combinations(level, environments, current, remaining_combinatoric_keys)
      else
        @logger.debug "#{indent}  Inferred environmentt: #{inspect_env(current)}"
        environments << current
      end
    end

    def inspect_env(env)
      result = []
      COMBINATORIC_KEYS.each do |key|
        if val = env[key]
          result << "#{key}=#{val}"
        end
      end
      result.join("; ")
    end

    def create_job_set(environments)
      environments.each_with_index do |environment, i|
        create_job(@job_set, environment, i + 1)
      end
      if @job_set.save
        @logger.info("Created job set with ID #{@job_set.id}. " +
          "It contains #{@job_set.jobs.count} jobs, with IDs #{@job_set.job_ids}")
        @logger.info("Creating repo cache...")
        if create_job_set_repo_cache
          @logger.info("Repo cache created.")
        else
          @logger.warn("Unable to create repository cache file for job set.")
        end
      else
        report_model_errors(@logger, @job_set)
        abort
      end
    end

    def job_set_repo_cache_path
      "#{job_set_path}/repo.tar.gz"
    end

    def create_job_set_repo_cache
      @logger.debug "Creating archive #{job_set_repo_cache_path}"
      system("env", "GZIP=-3", "tar", "-czf", job_set_repo_cache_path,
        ".", :chdir => "#{@work_dir}/repo")
    end

    def create_job(job_set, environment, number)
      @logger.info "Preparing job ##{number}: #{inspect_env(env)}"
      job = job_set.build
      job.number = number
      job.name = inspect_env(environment)
      job.environment = environment
      if !job.valid?
        report_model_errors(@logger, job)
        abort
      end
      job
    end
  end
end
