require 'shellwords'
require 'tmpdir'
require 'fileutils'

module ApachaiHopachai
  # Wrapper class for invoking Docker.
  class Docker
    module Shared
    private
      def esc(text)
        Shellwords.escape(text)
      end

      def logger
        @options[:logger]
      end

      def invoke(command)
        logger.debug("Invoking Docker: #{command}")
        system(command)
      end

      def capture_output(command)
        logger.debug("Invoking Docker: #{command}")
        `#{command}`
      end
    end

    include Shared

    class Session
      include Shared
      attr_reader :container_id

      def initialize(container_id, options = {})
        @container_id = container_id
        @options = options.dup
      end

      def close
        if @options[:temp_dir]
          FileUtils.remove_entry_secure(@options[:temp_dir]) rescue nil
        end
      end

      def docker_command
        self.class.docker_command(@options)
      end

      def kill
        invoke("#{docker_command} kill #{esc @container_id} >/dev/null")
      end

      def rm
        invoke("#{docker_command} rm #{esc @container_id} >/dev/null")
      end

      def wait
        invoke("#{docker_command} wait #{esc @container_id} >/dev/null")
      end

      def port(number)
        result = capture_output("#{docker_command} port #{esc @container_id} #{esc number}")
        result.strip!
        if result.empty?
          nil
        else
          result.to_i
        end
      end

      def inspect_container
        capture_output("#{docker_command} inspect #{esc @container_id}")
      end
    end

    def initialize(options = {})
      @options = options.dup
      raise ArgumentError, ":logger is required" if !@options[:logger]
    end

    def self.docker_command(options)
      if options[:sudo]
        "sudo docker"
      else
        "docker"
      end
    end

    def docker_command
      self.class.docker_command(@options)
    end

    def run(*command_inside_container)
      if command_inside_container.last.is_a?(Hash)
        options = command_inside_container.pop.dup
      else
        options = {}
      end
      bind_mounts = options.delete(:bind_mounts) || {}
      ports       = options.delete(:ports) || []
      tty         = options.delete(:tty)
      background  = options.delete(:background)
      image       = options.delete(:image)
      user        = options.delete(:user) || 'appa'
      if !options.empty?
        raise ArgumentError, "Unknown options: #{options.keys.inspect}"
      end
      if tty && background
        raise ArgumentError, "You cannot set both :tty and :background"
      end

      command = "#{docker_command} run "
      bind_mounts.each_pair do |host_path, container_path|
        command << "-v "
        command << esc("#{host_path}:#{container_path}") << " "
      end
      ports.each do |port|
        command << "-p #{esc port} "
      end
      command << "-t -i " if tty
      command << "-d " if background
      command << "-h #{esc image} " if image

      # Since bind mounts are read-write, we create a
      # "read-only" container_utils dir by making a copy
      # and bind mounting that instead.
      temp_dir = Dir.mktmpdir
      begin
        FileUtils.cp_r(CONTAINER_UTILS_DIR, temp_dir)
        command << "-v #{esc temp_dir}:/container_utils "

        command << "/usr/local/rvm/bin/rvm-exec ruby-2.0.0 "
        command << "ruby /container_utils/supervisor.rb "
        command << "sudo -u #{esc user} -H " if user
        command << Shellwords.join(command_inside_container)

        if background
          Session.new(capture_output(command).strip,
            @options.merge(:temp_dir => temp_dir))
        else
          begin
            invoke(command)
          ensure
            FileUtils.remove_entry_secure(temp_dir) rescue nil
            temp_dir = nil
          end
        end
      rescue Exception
        if temp_dir
          FileUtils.remove_entry_secure(temp_dir) rescue nil
        end
        raise
      end
    end

    def images
      capture_output("#{docker_command} images")
    end

    def ps(*args)
      command = "#{docker_command} ps "
      command << Shellwords.join(args)
      command.strip!
      capture_output(command)
    end
  end
end
