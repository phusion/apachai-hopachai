# encoding: utf-8
require_relative '../apachai-hopachai'
require_relative 'command_utils'

module ApachaiHopachai
  class RunCommand < Command
    include CommandUtils

    def self.description
      "Run a test job"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def self.require_libs
      require 'tmpdir'
      require 'shellwords'
      require_relative 'safe_yaml'
      require_relative 'database_models'
    end

    def start
      parse_argv
      maybe_set_log_file
      maybe_daemonize
      maybe_create_pid_file
      begin
        load_and_verify_job
        create_work_dir
        set_job_processing
        begin
          run_job
        rescue StandardError, SignalException => e
          set_job_errored
          exit(log_error(e))
        ensure
          destroy_work_dir
        end
      ensure
        maybe_destroy_pid_file
      end
    end

    private

    def option_parser
      require 'optparse'
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa run [OPTIONS] JOB_ID"
        opts.separator "Run a specific test job."
        opts.separator ""

        opts.separator "Options:"
        opts.on("--dry-run-test", "Do everything except running the actual test") do |val|
          @options[:dry_run_test] = true
        end
        opts.on("--sudo", "Call Docker using sudo") do |val|
          @options[:sudo] = true
        end
        opts.on("--bind-mount HOST_PATH:CONTAINER_PATH", "Bind mount a directory inside the container") do |val|
          host_path, container_path = val.split(':', 2)
          if !container_path
            abort "Invalid value for --bind-mount"
          end
          @options[:bind_mounts][host_path] = container_path
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
      @options = { :bind_mounts => {} }
      begin
        option_parser.parse!(@argv)
      rescue OptionParser::ParseError => e
        STDERR.puts e
        STDERR.puts
        STDERR.puts "Please see 'appa help run' for valid options."
        exit 1
      end

      if @options[:help]
        self.class.help
        exit 0
      end
      if @argv.size != 1
        self.class.help
        exit 1
      end
      if @options[:daemonize] && !@options[:log_file]
        abort "If you set --daemonize then you must also set --log-file."
      end
    end

    def load_and_verify_job
      begin
        @job = Job.find(@argv[0])
      rescue ActiveRecord::RecordNotFound
        abort "Job with ID #{@argv[0]} not found."
      end
      @job_set = @job.job_set
      @project = @job_set.project
    end

    def create_work_dir
      @work_dir = Dir.mktmpdir("appa-")
      Dir.mkdir("#{@work_dir}/input")
      Dir.mkdir("#{@work_dir}/output")
    end

    def destroy_work_dir
      # The sandbox container can create files that are owned by a different user, so use sudo.
      system("sudo", "rm", "-rf", "#{@work_dir}/output")
      FileUtils.remove_entry_secure(@work_dir)
    end

    def set_job_processing
      begin
        @job.set_processing!
      rescue Job::AlreadyProcessing
        abort "This job is already being processed."
      rescue ActiveRecord::StaleObjectError
        abort "Another process is currently processing this job."
      end
    end

    def run_job
      @logger.info "Running job ##{@job.number}: #{@job.name}"
      exit_code = run_job_script_and_extract_result
      if exit_code == 0
        @job.set_succeeded!
      else
        @job.set_failed!
      end
    end

    def run_job_script_and_extract_result
      File.open("#{@work_dir}/input/private_key", "w") do |f|
        f.chmod(0600)
        f.write(@project.private_key)
      end
      File.open("#{@work_dir}/input/project.json", "w") do |f|
        f.write(@project.to_json)
      end
      File.open("#{@work_dir}/input/job_set.json", "w") do |f|
        f.write(@job_set.to_json)
      end
      File.open("#{@work_dir}/input/job.json", "w") do |f|
        f.write(@job.to_json)
      end
      if File.exist?(@job_set.repo_cache_path)
        File.symlink(@job_set.repo_cache_path, "#{@work_dir}/input/repo.tar.gz")
      end

      command = "#{docker} run -d "
      @options[:bind_mounts].each_pair do |host_path, container_path|
        command << " -v #{Shellwords.escape host_path}:#{Shellwords.escape container_path} "
      end
      command << " -v #{Shellwords.escape ApachaiHopachai::APP_ROOT}:/appa:ro"
      command << " -v #{Shellwords.escape @work_dir}/input:/input:ro"
      command << " -v #{Shellwords.escape @work_dir}/output:/output"
      command << " #{SANDBOX_IMAGE_NAME} #{SUPERVISOR_COMMAND} #{SANDBOX_JOB_RUNNER_COMMAND}"
      command << " --dry-run" if @options[:dry_run_test]

      @logger.debug "Creating sandbox: #{command}"
      # The job runner will be blocked until we create the 'continue' file.
      @container = `#{command}`.strip
      @logger.info "Job run inside sandbox with container ID #{@container}"

      begin
        # Redirect logs to job log file.
        e_log_file = Shellwords.escape(@job.log_file_path)
        pid = Process.spawn("/bin/bash", "-c",
          "set -o pipefail -e; #{docker} logs -f #{@container} 2>&1 | tee #{e_log_file}",
          :in  => :in,
          :out => :out,
          :err => :err,
          :close_others => true)
        # Tell the job runner that it may now continue.
        File.open("#{@work_dir}/input/continue", "w").close

        # Wait until the container exits.
        exit_code = `#{docker} wait #{@container}`.strip.to_i
        Process.waitpid(pid)

        exit_code
      rescue Exception => e
        @logger.error "An error occurred. Killing sandbox."
        system("#{docker} kill #{@container} >/dev/null 2>/dev/null")
        raise e
      end
    end

    def set_job_errored
      begin
        @job.set_errored!
      rescue ActiveRecord::StaleObjectError
        @logger.warn("Unable to set job state to 'errored': job has been concurrently modified.")
      end
    end

    def log_error(e)
      if e.is_a?(SignalException)
        @logger.error "Interrupted by signal #{e.signo}"
      elsif !e.is_a?(Exited) || !e.logged?
        @logger.error("ERROR: #{e.message} (#{e.class}):\n    " +
          e.backtrace.join("\n    "))
      end

      if e.is_a?(Exited)
        e.exit_status
      else
        1
      end
    end

    def docker
      if @options[:sudo]
        "sudo docker"
      else
        "docker"
      end
    end
  end
end
