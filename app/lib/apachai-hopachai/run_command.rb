# encoding: utf-8
require 'apachai-hopachai'
require 'apachai-hopachai/command_utils'
require 'apachai-hopachai/jobset_utils'
require 'shellwords'

module ApachaiHopachai
  class RunCommand < Command
    include CommandUtils
    include JobsetUtils

    def self.description
      "Run a test job"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def self.require_libs
      require 'tmpdir'
      require 'safe_yaml'
    end

    def start
      parse_argv
      maybe_set_log_file
      maybe_daemonize
      maybe_create_pid_file
      begin
        read_and_verify_job
        create_work_dir
        begin
          @job.set_processing
          begin
            run_job
            save_result
            notify_jobset_changed
          ensure
            @job.unset_processing
          end
        rescue StandardError, SignalException => e
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
        opts.banner = "Usage: appa run [OPTIONS] JOB_PATH"
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--limit N", Integer, "Limit the number of environments to test. Default: test all environments") do |val|
          @options[:limit] = val
        end
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
        opts.on("--rerun", "Rerun job if job has already been processed") do
          @options[:rerun] = true
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

      @job_path = File.expand_path(@argv[0])
    end

    def read_and_verify_job
      jobset_path = File.dirname(@job_path)
      abort "The given job is not in a jobset" if jobset_path == @job_path
      abort "The given jobset does not exist" if !File.exist?(jobset_path)

      @job = Job.new(@job_path)
      abort "The given path is not a valid job" if !@job.valid?
      abort "Job is already being processed" if @job.processing?
      if @job.processed? && !@options[:rerun]
        abort "Job has already been processed. Use --rerun if you want to rerun this job"
      end

      @jobset = Jobset.new(jobset_path)
      abort "The given jobset is not complete" if !@jobset.complete?
      abort "Jobset format version #{@jobset.version} is unsupported" if !@jobset.version_supported?
    end

    def create_work_dir
      @work_dir = Dir.mktmpdir("appa-")
      Dir.mkdir("#{@work_dir}/output")
      # The job path can container the ':' character, which Docker does
      # not allow in -v. So we work around it with a symlink.
      File.symlink(@job_path, "#{@work_dir}/job")
    end

    def destroy_work_dir
      # The sandbox container can create files that are owned by a different user, so use sudo.
      system("sudo", "rm", "-rf", "#{@work_dir}/output")
      FileUtils.remove_entry_secure(@work_dir)
    end

    def run_job
      @logger.info "Running job with environment: #{@job.info['env_name']}"

      @run_result = { 'start_time' => Time.now }
      exit_code = run_job_script_and_extract_result
      @run_result['status'] = exit_code
      @run_result['passed'] = exit_code == 0
      @run_result['end_time'] = Time.now
      @run_result['duration'] = distance_of_time_in_hours_and_minutes(
        @run_result['start_time'], @run_result['end_time'])
    end

    def run_job_script_and_extract_result
      command = "#{docker} run -d "
      @options[:bind_mounts].each_pair do |host_path, container_path|
        command << " -v #{Shellwords.escape host_path}:#{Shellwords.escape container_path} "
      end
      command << " -v #{Shellwords.escape ApachaiHopachai::SOURCE_ROOT}:/appa:ro"
      command << " -v #{Shellwords.escape @work_dir}/job:/job"
      command << " -v #{Shellwords.escape @work_dir}/output:/output"
      command << " #{SANDBOX_IMAGE_NAME} #{SUPERVISOR_COMMAND} #{SANDBOX_JOB_RUNNER_COMMAND}"
      command << " --dry-run" if @options[:dry_run_test]

      @logger.debug "Creating container: #{command}"
      # The job runner will be blocked until we create the 'continue' file.
      @container = `#{command}`.strip
      @logger.info "Job run inside container with ID #{@container}"

      begin
        # Redirect logs to job log file.
        log_file = "#{@job_path}/output.log"
        pid = Process.spawn("/bin/bash", "-c",
          "set -o pipefail -e; #{docker} logs -f #{@container} 2>&1 | tee #{Shellwords.escape log_file}",
          :in  => :in,
          :out => :out,
          :err => :err,
          :close_others => true)
        # Tell the job runner that it may now continue.
        File.open("#{@work_dir}/output/continue", "w").close

        # Wait until the container exits.
        exit_code = `#{docker} wait #{@container}`.strip.to_i
        Process.waitpid(pid)

        exit_code
      rescue Exception => e
        @logger.error "An exception occurred. Killing container."
        system("#{docker} kill #{@container} >/dev/null 2>/dev/null")
        raise e
      end
    end

    def save_result
      filename = "#{@job_path}/result.yml"
      @logger.info "Saving result to #{filename}"
      File.open(filename, "w") do |io|
        YAML.dump(@run_result, io)
      end
    end

    def notify_jobset_changed
      now = Time.now
      File.utime(now, now, @jobset.path)
      File.utime(now, now, @jobset.path + "/..")
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

    def h(text)
      ERB::Util.h(text)
    end
  end
end
