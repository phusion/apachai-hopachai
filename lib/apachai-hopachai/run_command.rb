module ApachaiHopachai
  class RunCommand < Command
    COMBINATORIC_KEYS = ['rvm', 'env'].freeze

    def self.description
      "Run test"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def start
      require_libs
      parse_argv
      create_work_dir
      begin
        clone_repo
        extract_config_and_info
        environments = infer_test_environments
        #run_in_environments(environments)
        save_reports(environments)
        send_notifications(environments)
      ensure
        destroy_work_dir
      end
    end

    private

    def require_libs
      require 'apachai-hopachai/script_command'
      require 'tmpdir'
      require 'safe_yaml'
      require 'semaphore'
      require 'base64'
      require 'optparse'
      require 'thwait'
      require 'erb'
    end

    def option_parser
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa run [OPTIONS] GIT_URL"
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--limit N", Integer, "Limit the number of environments to test. Default: test all environments") do |val|
          @options[:limit] = val
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
        RunCommand.help
        exit 0
      end
      if @argv.size != 1
        RunCommand.help
        exit 1
      end

      @options[:repository] = @argv[0]
    end

    def create_work_dir
      @work_dir = Dir.mktmpdir("appa-")
      Dir.mkdir("#{@work_dir}/input")
      FileUtils.cp("#{ROOT}/travis-emulator-app/main", "#{@work_dir}/input/main")
    end

    def destroy_work_dir
      FileUtils.remove_entry_secure(@work_dir)
    end

    def clone_repo
      @logger.info "Cloning from #{@options[:repository]}"
      single_branch = "--single-branch" if `git clone --help` =~ /--single-branch/
      if !system("git clone --depth 1 #{single_branch} #{@options[:repository]} '#{@work_dir}/input/app'")
        abort "git clone failed"
      end
    end

    def extract_config_and_info
      @info = {
        :date => Time.now
      }

      Dir.chdir("#{@work_dir}/input/app") do
        lines = `git show --pretty='format:%h\n%an\n%cn\n%s' -s`.split("\n")
        @info[:commit], @info[:author], @info[:committer], @info[:subject] = lines
      end

      FileUtils.cp("#{@work_dir}/input/app/.travis.yml", "#{@work_dir}/travis.yml")
    end

    def infer_test_environments
      config = YAML.load_file("#{@work_dir}/travis.yml", :safe => true)
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
        environments = environments[0 .. @options[:limit] - 1]
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

    def run_in_environments(environments)
      semaphore = Semaphore.new(1)
      threads = []
      environments.each_with_index do |env, i|
        threads << Thread.new(env, i) do |_env, _i|
          Thread.current.abort_on_exception = true
          semaphore.synchronize do
            run_in_environment(_env, _i)
          end
        end
      end
      ThreadsWait.all_waits(*threads)
    end

    def run_in_environment(env, num)
      @logger.info "##{num} Running in environment: #{inspect_env(env)}"
      output_dir = "#{@work_dir}/output-#{num}"
      
      Dir.mkdir(output_dir)
      File.open("#{output_dir}/environment.txt", "w") do |f|
        f.puts(inspect_env(env))
      end

      script_command = ScriptCommand.new([
        "--script=#{@work_dir}/input",
        "--output=#{output_dir}/output.tar.gz",
        '--',
        @options[:repository],
        Base64.strict_encode64(Marshal.dump(env))
      ])
      script_command.run

      system("tar xzf output.tar.gz", :chdir => output_dir)
      File.unlink("#{output_dir}/output.tar.gz")
    end

    def save_reports(environments)
      @jobs = []
      @info[:duration] = distance_of_time_in_hours_and_minutes(@info[:date] - 30, Time.now)

      environments.each_with_index do |env, num|
        #output_dir = "#{@work_dir}/output-#{num}"
        output_dir = "output-0"
        @jobs << {
          :id     => num + 1,
          :name   => "##{num + 1}",
          :passed => File.read("#{output_dir}/runner.status") == "0\n",
          :duration => "TODO",
          :finished => "TODO",
          :env    => inspect_env(env),
          :log    => File.open("#{output_dir}/runner.log", "rb") { |f| f.read }
        }
      end

      @info[:passed] = @jobs.all? { |job| job[:passed] }
      @info[:state]  = @info[:passed] ? "Passed" : "Failed"
      @info[:finished] = "TODO"
      @info[:logo]   = File.open("#{ROOT}/src/logo.png", "rb") { |f| f.read }

      template = ERB.new(File.read("#{ROOT}/src/report.html.erb"))
      report = template.result(binding)
      File.open("report.html", "w") do |f|
        f.write(report)
      end
    end

    def send_notifications(environments)
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
