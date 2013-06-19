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
      parse_argv
      check_container_image_exists
      last_container = find_last_container
      run_shell
      if current_container = find_container_after(last_container)
        if @options[:commit]
          commit(current_container)
        end
        delete_container(current_container)
      else
        @logger.warn "Cannot deduct container ID."
      end
    end

    private

    def option_parser
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa shell [OPTIONS]"
        opts.separator "Starts a container shell session. This allows you to play around and test" +
          "things, or modify the container image if you specified --commit."
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--commit", "Commit changes to an image after the shell exits") do
          @options[:commit] = true
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
        STDERR.puts "Please see 'appa help shell' for valid options."
        exit 1
      end

      if @options[:help]
        ShellCommand.help
        exit 0
      end
    end

    def check_container_image_exists
      if `docker images` !~ /apachai-hopachai/
        abort "Container image apachai-hopachai does not exist. Please build it first with 'appa build'."
      end
    end

    def find_last_container
      lines = `docker ps -a`.split("\n")
      result = lines[1].to_s.split(/ +/)[0].to_s
      result.empty? ? nil : result
    end

    def run_shell
      result = system("docker run -t -i -h=apachai-hopachai -u=appa -p 3002 -p 3003 " +
        "apachai-hopachai sudo -u appa -H /bin/bash -l")
      exit 1 if !result
    end

    def find_container_after(last_container)
      @logger.debug { "docker ps -a says:\n#{`docker ps -a`}" }
      if last_container
        lines = `docker ps -a`.split("\n")
        lines.shift
        i = lines.find_index { |l| l.split(/ +/)[0] == last_container }
        if i > 0
          lines[i - 1].split(/ +/)[0]
        end
      else
        find_last_container
      end
    end

    def commit(container)
      @logger.info "Committing container #{container} to image apachai-hopachai"
      system("docker commit #{container} apachai-hopachai >/dev/null")
    end

    def delete_container(container)
      @logger.info "Deleting container #{container}"
      system("docker rm #{container} >/dev/null")
    end
  end
end