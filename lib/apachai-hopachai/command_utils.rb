# encoding: utf-8
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

    def pid_file_exists_and_is_valid?(filename)
      if File.exist?(filename)
        pid = File.read(filename).to_i
        if pid > 0
          begin
            Process.kill(0, pid)
            true
          rescue Errno::ESRCH
            false
          rescue SystemCallError => e
            true
          end
        else
          false
        end
      else
        false
      end
    end

    def create_pid_file(logger, filename)
      logger.info("Creating PID file: #{filename}")
      if pid_file_exists_and_is_valid?(filename)
        abort "According to the PID file, another instance is already running. Exiting."
      else
        File.open(filename, "w") do |f|
          f.puts Process.pid
        end
      end
    end

    def destroy_pid_file(logger, filename)
      if File.exist?(filename)
        logger.info("Deleting PID file: #{filename}")
        File.unlink(filename)
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

    def maybe_create_pid_file
      if @options[:pid_file]
        create_pid_file(@logger, @options[:pid_file])
      end
    end

    def maybe_destroy_pid_file
      if @options[:pid_file]
        destroy_pid_file(@logger, @options[:pid_file])
      end
    end

    def need_checking_for_system_symlinks?
      !NATIVELY_PACKAGED
    end

    def system_symlinks_exist?
      File.symlink?(WEBAPP_SYMLINK) && File.exist?(WEBAPP_SYMLINK)
    end

    def system_symlinks_correct?
      File.readlink(WEBAPP_SYMLINK) == WEBAPP_DIR
    end

    def check_symlinks
      if need_checking_for_system_symlinks?
        if system_symlinks_exist?
          if !system_symlinks_correct?
            message = "The system symlinks for Apachai Hopachai exist, but are broken."
          end
        else
          message = "The system symlinks for Apachai Hopachai don't exist!"
        end
        if message
          message = "!!! #{message}!! Please run this command to fix them:\n" +
            "\n" +
            "   # If you're using RVM:\n" +
            "   rvmsudo appa setup-symlinks\n" +
            "\n" +
            "   # If you're not using RVM, or don't know what RVM is:\n" +
            "   sudo appa setup-symlinks\n"
          if STDOUT.tty?
            @logger.warn("\e[33m\e[40m#{message}\e[0m")
          else
            @logger.warn(message)
          end
        end
      end
    end

    def check_container_image_exists(sudo = false)
      if sudo
        docker = "sudo docker"
      else
        docker = "docker"
      end
      if `#{docker} images` !~ /apachai-hopachai/
        abort "Container image 'apachai-hopachai' does not exist. Please build it first with 'appa build-image'."
      end
    end

    def options_to_args(options)
      args = []
      options.each_pair do |key, val|
        args << "--#{key.to_s.gsub(/_/, '-')}"
        args << val if val != true && val != false
      end
      args
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