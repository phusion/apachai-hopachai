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
      require_relative 'line_bufferer'
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
          dump_input_for_job_runner
          run_job
        rescue Exception => e
          set_job_errored
          if e.is_a?(StandardError) || e.is_a?(SignalException)
            exit(log_error(e))
          else
            raise e
          end
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
        opts.on("--timeout", Integer, "Maximum time for running the job") do |val|
          @options[:timeout] = val
        end
        opts.on("--idle-timeout", Integer, "Maximum time that the job may spent on not writing output") do |val|
          @options[:idle_timeout] = val
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
      @options = { :timeout => 60 * 60, :idle_timeout => 10 * 60, :bind_mounts => {} }
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
      @build = @job.build
      @project = @build.project
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

    def dump_input_for_job_runner
      File.open("#{@work_dir}/input/private_ssh_key", "w") do |f|
        f.chmod(0600)
        f.write(@project.private_ssh_key)
      end
      File.open("#{@work_dir}/input/project.json", "w") do |f|
        f.write(@project.to_json)
      end
      File.open("#{@work_dir}/input/build.json", "w") do |f|
        f.write(@build.to_json)
      end
      File.open("#{@work_dir}/input/job.json", "w") do |f|
        f.write(@job.to_json)
      end
      if File.exist?(@build.repo_cache_path)
        File.symlink(@build.repo_cache_path, "#{@work_dir}/input/repo.tar.gz")
      end
    end

    def run_job
      @logger.info "Running job ##{@job.number}: #{@job.name}"

      spawn_sandbox
      begin
        log_pipe = redirect_sandbox_logs
        exit_code = wait_for_sandbox(log_pipe)
      rescue Exception => e
        cleanup_sandbox(e)
      ensure
        close_pipes(log_pipe)
      end

      finalized = nil
      @build.transaction do
        if exit_code == 0
          @job.set_passed!
        else
          @job.set_failed!
        end
        finalized = @build.try_finalize!
      end
      if finalized
        @build.send_notifications
      end
    end

    def spawn_sandbox
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
      if $?.exitstatus == 0
        @logger.info "Job run inside sandbox with container ID #{@container}"
      else
        abort "Could not create sandbox."
      end
    end

    def redirect_sandbox_logs
      @logger.debug "Redirecting sandbox output to #{@job.log_file_path}"
      e_log_file = Shellwords.escape(@job.log_file_path)
      File.open(@job.log_file_path, "w").close
      pipe = IO.pipe
      begin
        pid = fork do
          begin
            Process.setsid
            Process.spawn("#{BIN_DIR}/better_tee #{e_log_file} #{docker} logs -f #{@container}",
              :in  => :in,
              :out => pipe[1],
              :err => :err,
              :close_others => true)
            exit!(0)
          rescue Exception => e
            STDERR.puts("#{e} (#{e.class})\n  " << e.backtrace.join("\n  "))
            exit!(1)
          ensure
            exit!(1)
          end
        end
        pipe[1].close
        Process.waitpid(pid)
        pipe[0].binmode
        pipe[0].sync = true

        # Give a small period of time for 'docker logs' to start, then tell
        # the job runner that it may continue.
        sleep 0.1
        File.open("#{@work_dir}/input/continue", "w").close

        pipe[0]
      rescue Exception => e
        close_pipes(*pipe)
        raise e
      end
    end

    def wait_for_sandbox(log_pipe)
      begin
        @logger.debug "Spawning 'docker wait'..."
        waiter_pipe_a, waiter_pipe_b = IO.pipe
        waiter_pid = Process.spawn("#{docker} wait #{@container}",
          :in  => :in,
          :out => waiter_pipe_b,
          :err => :err,
          :close_others => true)
        waiter_pipe_b.close

        # Wait until the sandbox exits,
        # or until the log file has been idle for too long,
        # or until the timeout passes.

        done      = false
        timed_out = false
        ios       = [log_pipe, waiter_pipe_a]
        deadline  = Time.now + @options[:timeout]
        last_output_time = Time.now
        exit_code_buffer = "".force_encoding("binary")
        line_bufferer = LineBufferer.new do |line|
          line = line.force_encoding("utf-8").scrub.chomp
          @logger.info("sandbox -- #{line}")
        end

        @logger.debug "Entering main wait loop."
        while !ios.empty?
          idle_deadline = last_output_time + @options[:idle_timeout]
          timeout = [deadline, idle_deadline].min - Time.now
          timeout = 0 if timeout < 0

          result = select(ios, nil, nil, timeout)
          if result
            result = result[0]
            if result.include?(log_pipe)
              # There is log activity.
              last_output_time = Time.now
              data, eof = drain_io(log_pipe)
              line_bufferer.add(data)
              if eof
                @logger.debug("Log tailer exited.")
                ios.delete(log_pipe)
              end
            end
            if result.include?(waiter_pipe_a)
              data, eof = drain_io(waiter_pipe_a)
              exit_code_buffer << data
              if eof
                @logger.debug("'docker wait' exited.")
                ios = []
              end
            end
          else
            @logger.debug "IO timeout."
            timed_out = true
            ios = []
          end
        end

        @logger.debug "Main wait loop exited."
        data, eof = drain_io(log_pipe)
        line_bufferer.add(data)
        line_bufferer.close

        if timed_out
          if Time.now >= deadline
            log_message = "*** The CI job has timed out and has been aborted."
            @logger.error("CI job timed out.")
          else
            log_message = "*** The CI job has not sent any output for too long and has been aborted."
            @logger.error("The CI job has not sent any output for too long.")
          end
          system("#{docker} kill #{@container} >/dev/null 2>/dev/null")
          @container = nil
          File.open(@job.log_file_path, "a") do |f|
            f.puts(log_message)
          end
          127
        else
          exit_code = exit_code_buffer.to_i
          @logger.debug("Sandbox exit code: #{exit_code}.")
          Process.waitpid(waiter_pid)
          waiter_pid = nil
          @container = nil
          exit_code
        end
      ensure
        kill_and_wait_no_error(waiter_pid)
        close_pipes(waiter_pipe_a, waiter_pipe_b)
      end
    end

    def drain_io(io)
      data = "".force_encoding("binary")
      eof = false
      while true
        begin
          data << io.read_nonblock(1024 * 16)
        rescue EOFError
          eof = true
          break
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EINTR => e
          break
        end
      end
      [data, eof]
    end

    def close_pipes(*args)
      args.each do |io|
        io.close if io && !io.closed?
      end
    end

    def kill_and_wait_no_error(pid)
      if pid
        begin
          Process.kill('TERM', pid)
        rescue Errno::EPERM, Errno::ECHILD, Errno::ESRCH
        end
        begin
          Process.waitpid(pid)
        rescue Errno::EPERM, Errno::ECHILD, Errno::ESRCH
        end
      end
    end

    def cleanup_sandbox(exception)
      if @container
        @logger.error "An error occurred. Killing sandbox."
        system("#{docker} kill #{@container} >/dev/null 2>/dev/null")
        File.open(@job.log_file_path, "a") do |f|
          f.puts "*** The administrator aborted this CI job."
        end
      end
      raise exception
    end

    def set_job_errored
      finalized = false
      @build.transaction do
        begin
          @job.set_errored!
          finalized = @build.try_finalize!
        rescue ActiveRecord::StaleObjectError
          @logger.warn("Unable to set job state to 'errored': job has been concurrently modified.")
        end
      end
      if finalized
        @build.send_notifications
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
