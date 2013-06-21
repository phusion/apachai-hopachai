require 'apachai-hopachai/command_utils'

module ApachaiHopachai
  class RunCommand < Command
    include CommandUtils

    def self.description
      "Run a test"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def start
      require_libs
      parse_argv
      maybe_set_log_file
      maybe_daemonize
      read_and_verify_plan
      create_work_dir
      begin
        run_plan
        save_result
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
      require 'thwait'
    end

    def option_parser
      require 'optparse'
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa run [OPTIONS] PLAN_PATH..."
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--limit N", Integer, "Limit the number of environments to test. Default: test all environments") do |val|
          @options[:limit] = val
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

      @plan_path = File.expand_path(@argv[0])
    end

    def read_and_verify_plan
      @planset_path = File.dirname(@plan_path)
      abort "The given plan is not in a planset" if @planset_path == @plan_path
      abort "The given planset is not complete" if !File.exist?("#{@planset_path}/info.yml")
      @planset_info = YAML.load_file("#{@planset_path}/info.yml", :safe => true)
      @plan_info = YAML.load_file("#{@plan_path}/info.yml", :safe => true)
      if @planset_info['file_version'] != '1.0'
        abort "Plan format version #{@planset_info['file_version']} is unsupported"
      end
      abort "Plan is already being processed" if plan_processing?
      abort "Plan has already been processed" if plan_processed?
    end

    def plan_processing?
      File.exist?("#{@plan_path}/processing")
    end

    def set_plan_processing!
      File.open("#{@plan_path}/processing", "w").close
    end

    def unset_plan_processing!
      File.unlink("#{@plan_path}/processing")
    end

    def plan_processed?
      File.exist?("#{@plan_path}/result.yml")
    end

    def create_work_dir
      @work_dir = Dir.mktmpdir("appa-")
    end

    def destroy_work_dir
      FileUtils.remove_entry_secure(@work_dir)
    end

    def run_plan
      @logger.info "# Running plan with environment: #{@plan_info[:env_name]}"
      set_plan_processing!

      @run_result = { 'start_time' => Time.now }
      run_plan_script_and_extract_result
      
      FileUtils.cp("#{@work_dir}/runner.log", "#{@plan_path}/output.log")
      @run_result['status'] = File.read("#{@work_dir}/runner.status").to_i
      @run_result['passed'] = @run_result['status'] == 0
      @run_result['end_time'] = Time.now
      @run_result['duration'] = distance_of_time_in_hours_and_minutes(
        @run_result['start_time'], @run_result['end_time'])
    end

    def run_plan_script_and_extract_result
      script_command = ScriptCommand.new([
        "--script=#{@plan_path}",
        "--output=#{@work_dir}/output.tar.gz",
        "--log-level=#{@logger.level}"
      ])
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
      filename = "#{@plan_path}/result.yml"
      @logger.info "Saving result to #{filename}"
      File.open(filename, "w") do |io|
        YAML.dump(@run_result, io)
      end
      unset_plan_processing!
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
