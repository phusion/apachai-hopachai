require 'optparse'

module ApachaiHopachai
  class ShellCommand < Command
    def self.description
      "Start the container and run a shell in it"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def start
      result = system("docker run -t -i -h=apachai-hopachai -u=appa -p 3002 -p 3003 " +
        "apachai-hopachai sudo -u appa /bin/bash -l")
      exit 1 if !result
      if @options[:commit]
        system("docker ")
      end
    end

    private

    def option_parser
      OptionParser.new do |opts|
      nl = "\n#{' ' * 37}"
      opts.banner = "Usage: appa shell [OPTIONS]"
      opts.separator ""
      
      opts.separator "Options:"
      opts.on("--commit", "Commit changes to the container after the shell exits") do
        @options[:commit] = true
      end
      opts.on("--help", "-h", "Show help message") do
        @options[:help] = true
      end
    end

    def parse_argv
      @options = {}
      begin
        option_parser.parse!(@argv)
      rescue OptionParser::ParseError => e
        STDERR.puts e
        STDERR.puts
        STDERR.puts "Please see 'appa help shell' for valid options."
        exit 1
      end

      if @options[:help]
        ShellCommand.help
        exit 0
      end
    end
  end
end