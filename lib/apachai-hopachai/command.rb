require 'logger'

module ApachaiHopachai
  class Exited < StandardError
    attr_reader :exit_status, :logged
    alias logged? logged

    def initialize(exit_status, message = nil, logged = false)
      super(message || self.class.to_s)
      @exit_status = exit_status
      @logged = logged
    end
  end

  RESOURCES_DIR = File.expand_path(File.dirname(__FILE__) + "/../../resources")

  COMMANDS = {
    'build'    => 'BuildCommand',
    'prepare'  => 'PrepareCommand',
    'run'      => 'RunCommand',
    'finalize' => 'FinalizeCommand',
    'daemon'   => 'DaemonCommand',
    'script'   => 'ScriptCommand',
    'shell'    => 'ShellCommand',
    'help'     => 'HelpCommand'
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
    attr_accessor :logger

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

    def exit(code = 0)
      raise Exited.new(code, nil, true)
    end

    def abort(message = nil)
      if message
        @logger.fatal(message)
        e = Exited.new(1, message, true)
      else
        e = Exited.new(1, message, false)
      end
      raise e
    end
  end
end