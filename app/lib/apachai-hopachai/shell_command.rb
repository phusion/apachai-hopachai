# encoding: utf-8
require_relative '../apachai-hopachai'
require_relative 'command_utils'
require 'optparse'
require 'shellwords'

module ApachaiHopachai
  class ShellCommand < Command
    include CommandUtils

    def self.description
      "Run a shell inside a sandbox"
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
        opts.on("--bind-mount HOST_PATH:CONTAINER_PATH", "Bind mount a directory inside the container") do |val|
          host_path, container_path = val.split(':', 2)
          if !container_path
            abort "Invalid value for --bind-mount"
          end
          @options[:bind_mounts][host_path] = container_path
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
      @options = { :bind_mounts => {} }
      begin
        option_parser.parse!(@argv)
      rescue OptionParser::ParseError => e
        STDERR.puts e
        STDERR.puts
        STDERR.puts "Please see 'appa help shell' for valid options."
        exit 1
      end

      if @options[:help]
        self.class.help
        exit 0
      end
    end

    def find_last_container
      lines = `docker ps -a`.split("\n")
      result = lines[1].to_s.split(/ +/)[0].to_s
      result.empty? ? nil : result
    end

    def run_shell
      command = "docker run -t -i"
      @options[:bind_mounts].each_pair do |host_path, container_path|
        command << " -v #{Shellwords.escape host_path}:#{Shellwords.escape container_path}"
      end
      command << " -v #{Shellwords.escape  ApachaiHopachai::SOURCE_ROOT}:/appa:ro"
      command << " #{SANDBOX_IMAGE_NAME} #{SUPERVISOR_COMMAND}"
      command << " sudo -u appa -H /bin/bash -l"
      @logger.info "Running: #{command}"
      result = system(command)
      exit 1 if !result
    end

    def find_container_after(last_container)
      @logger.debug { "docker ps -a says:\n#{`docker ps -a`}" }
      if last_container
        lines = `docker ps -a`.split("\n")
        lines.shift
        i = lines.find_index { |l| l.split(/ +/)[0] == last_container }
        if i && i > 0
          lines[i - 1].split(/ +/)[0]
        else
          nil
        end
      else
        find_last_container
      end
    end

    def commit(container)
      @logger.info "Committing container #{container} to image #{SANDBOX_IMAGE_NAME}"
      system("docker commit #{container} #{SANDBOX_IMAGE_NAME} >/dev/null")
    end

    def delete_container(container)
      @logger.info "Deleting container #{container}"
      system("docker rm #{container} >/dev/null")
    end
  end
end