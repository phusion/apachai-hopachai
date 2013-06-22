require 'apachai-hopachai/command_utils'

module ApachaiHopachai
  class RunCommand < Command
    include CommandUtils

    def self.description
      "Run a test job"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def start
      require_libs
      parse_argv
      maybe_set_log_file
      maybe_daemonize
      read_and_verify_job
      create_work_dir
      begin
        set_job_processing
        begin
          run_job
          save_result
        ensure
          unset_job_processing
        end
      rescue StandardError, SignalException => e
        exit(log_error(e))
      ensure
        destroy_work_dir
      end
    end

    private

    def require_libs
      require 'apachai-hopachai/script_command'
      require 'tmpdir'
      require 'safe_yaml'
    end

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
        opts.on("--daemonize", "-d", "Daemonize into background") do
          @options[:daemonize] = true
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
      @options = {}
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
      @jobset_path = File.dirname(@job_path)
      abort "The given job is not in a jobset" if @jobset_path == @job_path
      abort "The given jobset does not exist" if !File.exist?(@jobset_path)
      abort "The given jobset is not complete" if !File.exist?("#{@jobset_path}/info.yml")
      
      jobset_info = YAML.load_file("#{@jobset_path}/info.yml", :safe => true)
      if jobset_info['file_version'] != '1.0'
        abort "job format version #{jobset_info['file_version']} is unsupported"
      end

      @job_info = YAML.load_file("#{@job_path}/info.yml", :safe => true)
      abort "job is already being processed" if job_processing?
      abort "job has already been processed" if job_processed?
    end

    def job_processing?
      File.exist?("#{@job_path}/processing")
    end

    def set_job_processing
      File.open("#{@job_path}/processing", "w").close
    end

    def unset_job_processing
      File.unlink("#{@job_path}/processing")
    end

    def job_processed?
      File.exist?("#{@job_path}/result.yml")
    end

    def create_work_dir
      @work_dir = Dir.mktmpdir("appa-")
    end

    def destroy_work_dir
      FileUtils.remove_entry_secure(@work_dir)
    end

    def run_job
      @logger.info "Running job with environment: #{@job_info['env_name']}"

      @run_result = { 'start_time' => Time.now }
      run_job_script_and_extract_result
      
      FileUtils.cp("#{@work_dir}/runner.log", "#{@job_path}/output.log")
      @run_result['status'] = File.read("#{@work_dir}/runner.status").to_i
      @run_result['passed'] = @run_result['status'] == 0
      @run_result['end_time'] = Time.now
      @run_result['duration'] = distance_of_time_in_hours_and_minutes(
        @run_result['start_time'], @run_result['end_time'])
    end

    def run_job_script_and_extract_result
      script_command = ScriptCommand.new([
        "--script=#{@job_path}",
        "--output=#{@work_dir}/output.tar.gz",
        "--log-level=#{@logger.level}",
        "--",
        @options[:dry_run_test] ? "--dry-run" : nil
      ].compact)
      # Let any exceptions propagate so that bugs in Apachai Hopachai trigger
      # a stack trace. If the test inside the container fails, no exception
      # will be thrown. Instead we'll find a non-zero status in the status file.
      script_command.start

      pid = Process.spawn("tar", "xzf", "output.tar.gz",
        :chdir => @work_dir)
      begin
        Process.waitpid(pid)
      rescue SignalException
        Process.kill('TERM', pid)
        Process.waitpid(pid) rescue nil
        raise
      end

      if $?.exitstatus != 0
        abort "Cannot extract test output"
      end
    end

    def save_result
      filename = "#{@job_path}/result.yml"
      @logger.info "Saving result to #{filename}"
      File.open(filename, "w") do |io|
        YAML.dump(@run_result, io)
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

    def h(text)
      ERB::Util.h(text)
    end

    def distance_of_time_in_hours_and_minutes(from_time, to_time)
      from_time = from_time.to_time if from_time.respond_to?(:to_time)
      to_time = to_time.to_time if to_time.respond_to?(:to_time)
      dist = (to_time - from_time).to_i
      minutes = (dist.abs / 60).round
      hours = minutes / 60
      minutes = minutes - (hours * 60)
      seconds = dist - (hours * 3600) - (minutes * 60)

      words = ''
      words << "#{hours} #{hours > 1 ? 'hours' : 'hour' } " if hours > 0
      words << "#{minutes} min " if minutes > 0
      words << "#{seconds} sec"
    end
  end
end
