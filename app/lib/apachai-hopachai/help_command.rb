# encoding: utf-8

module ApachaiHopachai
  class HelpCommand < Command
    def self.description
      "Show all commands"
    end

    def self.help
      puts "Usage: appa help <COMMAND>"
      puts "Shows the help message for a command."
    end

    def start
      if @argv.empty?
        list_commands
      elsif @argv.size == 1
        show_help_for_command(@argv[0])
      else
        show_help_for_command("help")
        exit 1
      end
    end

    private

    def list_commands
      puts "Usage: appa <COMMAND> [OPTIONS]"
      puts
      puts "Available commands:"
      puts
      COMMANDS.each_pair do |command_name, class_name|
        printf "  %-10s  %s\n",
          command_name,
          ApachaiHopachai.get_class_for_command(command_name).description
      end
      puts
      puts "Run `appa help <COMMAND>` to learn more about a command."
    end

    def show_help_for_command(command_name)
      klass = ApachaiHopachai.get_class_for_command(command_name)
      if klass
        require 'optparse'
        klass.help
      else
        STDERR.puts "Command #{command_name} not recognized. Please run 'appa help' for an overview of commands."
        exit 1
      end
    end
  end
end