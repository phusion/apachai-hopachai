module ApachaiHopachai
  class PrepareCommand < Command
    COMBINATORIC_KEYS = ['rvm', 'env'].freeze

    def self.description
      "Prepare test runs"
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
      set_log_file(@options[:log_file]) if @options[:log_file]
      daemonize(@logger) if @options[:daemonize]
      create_work_dir
      begin
        clone_repo
        extract_config_and_info
        environments = infer_test_environments
        create_plans(environments)
      ensure
        destroy_work_dir
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
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--output-dir DIR", "-o", String, "Store prepared plans in this directory") do |val|
          @options[:output_dir] = val
        end
        opts.on("--save-paths FILENAME", String, "Store path names of prepared plans into this file") do |val|
          @options[:save_paths] = val
        end
        opts.on("--limit N", Integer, "Limit the number of environments to prepare. Default: prepare all environments") do |val|
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

      @options[:repository] = @argv[0]
      @options[:commit] = @argv[1]
    end

    def create_work_dir
      @work_dir = Dir.mktmpdir("appa-")
      FileUtils.cp("#{ROOT}/travis-emulator-app/main", "#{@work_dir}/main")
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

      if !system("git clone #{args.join(' ')} #{@options[:repository]} '#{@work_dir}/app'")
        abort "git clone failed"
      end

      if @options[:commit]
        system("git", "checkout", "-q", @options[:commit], :chdir => "#{@work_dir}/app")
      end
    end

    def extract_config_and_info
      @info = {
        :file_version => '1.0',
        :start_time => Time.now
      }
      Dir.chdir("#{@work_dir}/app") do
        lines = `git show --pretty='format:%h\n%an\n%cn\n%s' -s`.split("\n")
        @info[:commit], @info[:author], @info[:committer], @info[:subject] = lines
      end
    end

    def infer_test_environments
      config = YAML.load_file("#{@work_dir}/app/.travis.yml", :safe => true)
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

    def create_plans(environments)
      if @options[:save_paths]
        save_file = File.open(@options[:save_paths], "w")
      end

      begin
        environments.each_with_index do |env, i|
          @logger.info "Preparing plan ##{i + 1}: #{inspect_env(env)}"
          path = File.expand_path(@options[:output_dir] +
            "/appa-#{Time.now.strftime("%Y-%m-%d-%H:%M:%S")}-#{i + 1}")
          @logger.info "Saving plan into #{path}"

          begin
            Dir.mkdir(path)
            FileUtils.cp_r(Dir["#{@work_dir}/*"], path)
            File.open("#{path}/travis.yml", "w") do |io|
              YAML.dump(env, io)
            end
            File.open("#{path}/info.yml", "w") do |io|
              YAML.dump(@info, io)
            end
          rescue Exception
            FileUtils.remove_entry_secure(path)
            raise
          end
          if save_file
            save_file.puts(path)
            save_file.flush
          end
        end
      ensure
        if @options[:save_paths]
          save_file.close
        end
      end
    end
  end
end
