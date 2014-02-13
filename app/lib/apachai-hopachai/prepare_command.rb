# encoding: utf-8
require_relative 'command_utils'
require 'shellwords'

module ApachaiHopachai
  class PrepareCommand < Command
    include CommandUtils

    COMBINATORIC_KEYS = ['rvm', 'env'].freeze

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
          clone_repo
          extract_repo_info
          environments = infer_test_environments
          create_jobset(environments)
          notify_jobset_changed
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
    end

    def option_parser
      require 'optparse'
      @options = {}
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa prepare [OPTIONS] GIT_URL [COMMIT]"
        opts.separator "Prepare running test jobs on the given git repository."
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--output-dir DIR", "-o", String, "Store prepared jobs in this directory") do |val|
          @options[:output_dir] = val
        end
        opts.on("--limit N", Integer, "Limit the number of environments to prepare. Default: prepare all environments") do |val|
          @options[:limit] = val
        end
        opts.on("--repo-name NAME", String, "A friendly name for the repository, to display in reports") do |val|
          @options[:repo_name] = val
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
      if !@options[:output_dir]
        abort "You must set --output-dir."
      end
      if @options[:daemonize] && !@options[:log_file]
        abort "If you set --daemonize then you must also set --log-file."
      end
      if !File.exist?(@options[:output_dir])
        abort "The output directory #{@options[:output_dir]} does not exist."
      end
      if !File.directory?(@options[:output_dir])
        abort "The output path #{@options[:output_dir]} is not a directory."
      end

      @options[:repository] = @argv[0]
      @options[:commit] = @argv[1]
    end

    def create_work_dir
      @work_dir = Dir.mktmpdir("appa-")
    end

    def destroy_work_dir
      FileUtils.remove_entry_secure(@work_dir)
    end

    def clone_repo
      if @options[:commit]
        @logger.info "Cloning from #{@options[:repository]}, commit #{@options[:commit]}"
      else
        @logger.info "Cloning from #{@options[:repository]}"
      end

      args = []
      if !@options[:commit]
        args << "--single-branch" if `git clone --help` =~ /--single-branch/
        args << "--depth 1"
      end

      if !system("git clone #{args.join(' ')} #{@options[:repository]} '#{@work_dir}/repo'")
        abort "Git clone failed"
      end

      if @options[:commit]
        if !system("git", "checkout", "-q", @options[:commit], :chdir => "#{@work_dir}/repo")
          abort "Unable to checkout commit #{@options[:commit]}"
        end
      end
    end

    def extract_repo_info
      @repo_info = {}
      e_dir = Shellwords.escape("#{@work_dir}/repo")
      lines = `cd #{e_dir} && git show --pretty='format:%h\n%H\n%an\n%ae\n%cn\n%ce\n%s' -s`.split("\n")
      @repo_info['commit'],
        @repo_info['sha'],
        @repo_info['author'],
        @repo_info['author_email'],
        @repo_info['committer'],
        @repo_info['committer_email'],
        @repo_info['subject'] = lines
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

    def create_jobset(environments)
      @logger.info "Creating jobset: #{jobset_path}"
      Dir.mkdir(jobset_path)
      begin
        if !create_jobset_repo_archive
          abort "Unable to create repository archive file #{jobset_repo_archive_path}"
        end

        environments.each_with_index do |env, i|
          create_job(env, i)
        end

        @logger.info "Committing jobset #{jobset_path}"
        File.open("#{jobset_path}/info.yml", "w") do |io|
          YAML.dump(jobset_info, io)
        end
      rescue Exception => e
        @logger.error "An error occurred. Deleting jobset."
        FileUtils.remove_entry_secure(jobset_path)
        raise e
      end
    end

    def jobset_repo_archive_path
      "#{jobset_path}/repo.tar.gz"
    end

    def create_jobset_repo_archive
      @logger.debug "Creating archive #{jobset_repo_archive_path}"
      system("env", "GZIP=-3", "tar", "-czf", jobset_repo_archive_path,
        ".", :chdir => "#{@work_dir}/repo")
    end

    def create_job(env, i)
      path = job_path(env, i)
      @logger.info "Preparing job ##{i + 1}: #{inspect_env(env)}"
      @logger.info "Saving job into #{path}"

      Dir.mkdir(path)
      begin
        File.open("#{path}/travis.yml", "w") do |io|
          YAML.dump(env, io)
        end
        File.open("#{path}/info.yml", "w") do |io|
          YAML.dump(job_info(env, i), io)
        end
      rescue Exception
        FileUtils.remove_entry_secure(path)
        raise
      end

      path
    end

    def notify_jobset_changed
      now = Time.now
      File.utime(now, now, jobset_path)
      File.utime(now, now, jobset_path + "/..")
    end

    def job_path(env, i)
      File.expand_path("#{jobset_path}/#{i + 1}.appa-job")
    end

    def job_info(env, i)
      {
        'id' => i + 1,
        'name' => "##{i + 1}",
        'created_at' => Time.now,
        'env_name' => inspect_env(env)
      }
    end

    def jobset_path
      @jobset_path ||= File.expand_path(@options[:output_dir] +
        "/" + Time.now.strftime("%Y-%m-%d-%H:%M:%S") + "-#{Process.pid}.appa-jobset")
    end

    def jobset_info
      result = @repo_info.dup

      if @options[:before_sha]
        result['before_sha'] = @options[:before_sha]
      else
        result['before_sha'] = result['sha']
      end
      result['before_commit'] = shorten_sha(result['before_sha'])

      result['repo_url'] = @options[:repository]
      if @options[:repo_name]
        result['repo_name'] = @options[:repo_name]
      else
        result['repo_name'] = @options[:repository].sub(/.*\//, '')
      end

      result['file_version'] = '1.0'
      result['preparation_time'] = Time.now

      result
    end

    def shorten_sha(sha)
      sha[0..6]
    end
  end
end
