module ApachaiHopachai
  class RunCommand < Command
    COMBINATORIC_KEYS = ['env', 'rvm'].freeze

    def self.description
      "Run test"
    end

    def start
      @logger.level = Logger::DEBUG
      parse_argv
      require_libs
      create_work_dir
      begin
        clone_repo
        extract_config
        environments = infer_test_environments
        run_in_environments(environments)
      ensure
        destroy_work_dir
      end
    end

    private

    def parse_argv
      @options = {
        :repository => @argv[0]
      }
    end

    def require_libs
      require 'apachai-hopachai/script_command'
      require 'tmpdir'
      require 'safe_yaml'
      require 'base64'
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

    def extract_config
      @logger.info "Extracting Travis config file"
      FileUtils.cp("#{@work_dir}/input/app/.travis.yml", "#{@work_dir}/travis.yml")
    end

    def infer_test_environments
      config = YAML.load_file("#{@work_dir}/travis.yml", :safe => true)
      environments = []
      traverse_combinations(0, environments, config, COMBINATORIC_KEYS)
      @logger.info "Inferred #{environments.size} test environments"
      environments.each do |env|
        @logger.debug "  #{inspect_env(env)}"
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
            @logger.debug "#{indent}  Inferred environment: #{inspect_env(current_env)}"
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
      environments = [environments.first]

      environments.each_with_index do |env, i|
        @logger.info "##{i} Running in environment: #{inspect_env(env)}"
        script_command = ScriptCommand.new([
          "--script=#{@work_dir}/input",
          "--output=#{@work_dir}/output-#{i}.tar.gz",
          '--log-level=debug',
          '--',
          @options[:repository],
          Base64.strict_encode64(Marshal.dump(env))
        ])
        script_command.run
      end
    end
  end
end
