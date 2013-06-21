module ApachaiHopachai
  module CommandUtils
    private

    def set_log_level(name)
      case name
      when "fatal"
        @logger.level = Logger::FATAL
      when "error"
        @logger.level = Logger::ERROR
      when "warn"
        @logger.level = Logger::WARN
      when "info"
        @logger.level = Logger::INFO
      when "debug"
        @logger.level = Logger::DEBUG
      when /^[0-9]+$/
        @logger.level = name.to_i
      else
        abort "Unknown log level #{name.inspect}"
      end
    end

    def set_log_file(log_file)
      file = File.open(log_file, "a")
      STDOUT.reopen(file)
      STDERR.reopen(file)
      STDOUT.sync = STDERR.sync = file.sync = true
    end

    def daemonize(logger)
      logger.info("Daemonization requested.")
      pid = fork
      if pid
        # Parent
        exit!(0)
      else
        # Child
        trap "HUP", "IGNORE"
        STDIN.reopen("/dev/null", "r")
        Process.setsid
        logger.info("Daemonized into background: PID #{$$}")
      end
    end

    def maybe_set_log_file
      if @options[:log_file]
        set_log_file(@options[:log_file])
      end
    end

    def maybe_daemonize
      if @options[:daemonize]
        daemonize(@logger)
      end
    end
  end
end