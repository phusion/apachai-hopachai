require 'optparse'
require 'socket'
require 'base64'

module ApachaiHopachai
  class RunCommand < Command
    def self.description
      "Run an app inside the container"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def start
      parse_argv
      create_or_use_container
      begin
        wait_for_connection
        begin
          send_input
          begin_watching_status
          begin
            receive_and_save_output
            send_notifications
          ensure
            stop_watching_status
          end
        ensure
          close_connection
        end
      rescue => e
        report_error(e)
        exit 1
      ensure
        maybe_destroy_container
      end
    end

    private

    def option_parser
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa run [OPTIONS] arguments..."
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--app DIR", "-a", String, "The app to run") do |val|
          @options[:app_dir] = val
        end
        opts.on("--container ID", String, "Use existing container instead of creating one") do |val|
          @options[:container] = val
        end
        opts.on("--output FILENAME", "-o", String, "The file to store the output to") do |val|
          @options[:output] = val
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
      @options = {}
      begin
        option_parser.parse!(@argv)
      rescue OptionParser::ParseError => e
        STDERR.puts e
        STDERR.puts
        STDERR.puts "Please see 'appa help run' for valid options."
        exit 1
      end

      if @options[:help]
        RunCommand.help
        exit 0
      end
      if !@options[:app_dir]
        STDERR.puts "Please specify an app to run with '--app'."
        exit 1
      end
      if !@options[:output]
        STDERR.puts "Please specify an app to run with '--output'."
        exit 1
      end
    end

    def create_or_use_container
      if should_create_new_container?
        @logger.debug "Creating container"
        command = "docker run -d -h=apachai-hopachai -u=appa -p 3002,3003 apachai-hopachai " +
          "sudo -u appa /usr/local/rvm/bin/rvm-exec 1.9.3 ruby /bootstrap.rb"
        @container = `#{command}`.strip
        @logger.info "Created container with ID #{@container}"
      else
        @container = @options[:container]
        @logger.info "Using existing container with ID #{@container}"
      end
    end

    def maybe_destroy_container
      if should_create_new_container?
        @logger.info "Destroying container"
        system("docker kill #{@container} >/dev/null")
        system("docker rm #{@container} >/dev/null")
      end
    end

    def should_create_new_container?
      !@options[:container]
    end

    def wait_for_connection
      sleep 1
      @logger.debug("Querying host port for Docker container port 3002")
      @main_port = `docker port #{@container} 3002`.to_i
      abort "Cannot query host port for Docker container port 3002" if @main_port == 0
      @logger.debug("Host port for Docker container port 3002 is #{@main_port}")
      @logger.info("Connecting to container")
      @main_socket = TCPSocket.new('127.0.0.1', @main_port)
      @main_socket.sync = true
      @main_socket.binmode
    end

    def close_connection
      @main_socket.close
    end

    def send_input
      @logger.info "Sending input"

      @logger.debug "Sending runner"
      write_string(@main_socket, File.read("#{ROOT}/src/runner.rb"))

      @logger.debug "Sending options"
      write_string(@main_socket, Marshal.dump(:args => @argv))

      @logger.debug "Sending application files"
      Dir.chdir(@options[:app_dir]) do
        IO.popen("tar -c . | gzip --best", "rb") do |io|
          size = 0
          while !io.eof?
            buf = io.readpartial(1024 * 32)
            write_string(@main_socket, buf)
            size += buf.size
            @logger.debug "  --> Written #{size} bytes so far"
          end
          @logger.debug "  --> Done"
          write_string(@main_socket, nil)
        end
      end
    end

    def receive_and_save_output
      @logger.info "Receiving and saving output to file #{@options[:output]}"
      File.open(@options[:output], "wb") do |f|
        size = 0
        while true
          buf = read_string(@main_socket)
          break if buf.nil?
          f.write(buf)
          f.flush
          size += buf.size
          @logger.debug "  --> Saved #{size} bytes so far"
        end
        @logger.debug "  --> Done"
      end
    end

    def send_notifications
      # TODO
    end

    def begin_watching_status
      # TODO
    end

    def stop_watching_status
      # TODO
    end

    def report_error(e)
      @logger.error("ERROR: #{e.message} (#{e.class}):\n    " +
          e.backtrace.join("\n    "))
      @logger.error("You can see the Docker logs with: docker logs #{@container}")
    end

    def write_string(socket, str)
      if str.nil?
        socket.write("\n")
      else
        socket.puts(Base64.strict_encode64(str))
      end
    end

    def read_string(socket)
      line = socket.readline
      if line == "\n"
        nil
      else
        Base64.decode64(line).force_encoding('binary')
      end
    end
  end
end