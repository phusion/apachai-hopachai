require 'logger'

module ApachaiHopachai
  class Exited < StandardError
    attr_reader :exit_status

    def initialize(exit_status, message = nil)
      super(message || self.class.to_s)
      @exit_status = exit_status
    end
  end

  ROOT = File.expand_path(File.dirname(__FILE__) + "/../..")

  COMMANDS = {
    'build' => 'BuildCommand',
    'run'   => 'RunCommand',
    'shell' => 'ShellCommand',
    'help'  => 'HelpCommand'
  }

  def self.get_class_for_command(command_name)
    class_name = COMMANDS[command_name]
    if class_name
      filename = command_name.gsub(/-/, '_')
      require "apachai-hopachai/#{filename}_command"
      ApachaiHopachai.const_get(class_name)
    else
      nil
    end
  end

  class Command
    attr_reader :exit_status

    def self.description
      nil
    end

    def initialize(argv = [])
      @argv   = argv.dup
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO
      @exit_status = 0
    end

    def run
      start
    rescue Exited => e
      @exit_status = e.exit_status
    end

    private

    def abort(message = nil)
      @logger.fatal(message) if message
      exit(1, message)
    end

    def exit(code = 0, message = nil)
      raise Exited.new(code, message)
    end

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
      else
        abort "Unknown log level #{name.inspect}"
      end
    end
  end
end