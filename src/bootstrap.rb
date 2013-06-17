#!/usr/bin/env ruby
abort "This tool must be run in Ruby 1.9" if RUBY_VERSION <= '1.9'

require 'socket'
require 'logger'
require 'fileutils'
require 'base64'

class Bootstrap
  WORK_DIR = "/home/appa/work"

  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::DEBUG
  end

  def start
    create_work_directory
    start_server
    receive_input
    execute_runner
    package_and_send_output
  end

  private

  def create_work_directory
    FileUtils.rm_rf(WORK_DIR)
    Dir.mkdir(WORK_DIR)
    Dir.mkdir("#{WORK_DIR}/output")
  end

  def start_server
    @logger.debug "Starting server at port 3002"
    @server = TCPServer.new('0.0.0.0', 3002)
    @logger.info "Waiting for connection from host"
    @client = @server.accept
    @logger.info "Connection accepted"
    @client.sync = true
    @client.binmode
  end

  def receive_input
    @logger.info "Receiving input"

    @logger.debug "Receiving and saving runner source"
    runner_source = read_string(@client)
    File.open("#{WORK_DIR}/runner.rb", "wb") do |f|
      f.write(runner_source)
    end

    @logger.debug "Receiving options"
    @options = Marshal.load(read_string(@client))
    @logger.info "Received options are: #{@options.inspect}"

    @logger.debug "Receiving and saving application files"
    File.open("#{WORK_DIR}/app.tar.gz", "wb") do |f|
      size = 0
      while true
        buf = read_string(@client)
        break if buf.nil?
        f.write(buf)
        size += buf.size
        @logger.debug "  -> Received #{size} bytes so far"
      end
      @logger.debug "  -> Done"
    end

    @logger.debug "Extracting app.tar.gz"
    Dir.chdir(WORK_DIR) do
      if !system("tar xzf app.tar.gz")
        abort "Error extracting tarball"
      end
    end
  end

  def execute_runner
    @logger.info "Executing runner"

    File.open("#{WORK_DIR}/output/runner.log", "w").close
    a, b = IO.pipe
    tee_pid = Process.spawn("tee", "#{WORK_DIR}/output/runner.log",
      :in => a,
      :out => :out,
      :err => :err)
    a.close

    begin
      args = ["/usr/local/rvm/bin/rvm-exec", "1.9.3", "ruby", "./runner.rb"]
      args.concat(@options[:args])
      args << {
        :in => ["/dev/null", "w"],
        :out => b,
        :err => b,
        :chdir => WORK_DIR
      }
      pid = Process.spawn(*args)
      b.close
      Process.waitpid(pid)
      status = $?.exitstatus
      @logger.info "Runner exited with status #{status}"
      File.open("#{WORK_DIR}/output/runner.status", "w") do |f|
        f.puts(status.to_s)
      end
    ensure
      Process.waitpid(tee_pid)
    end
  end

  def package_and_send_output
    @logger.info "Packaging and sending output"
    Dir.chdir("#{WORK_DIR}/output") do
      if !system("tar -c . | gzip --best > ../output.tar.gz")
        abort "Cannot package output"
      end
    end
    File.open("#{WORK_DIR}/output.tar.gz", "rb") do |f|
      size = 0
      while !f.eof?
        buf = f.readpartial(1024 * 32)
        write_string(@client, buf)
        size += buf.size
        @logger.debug "  -> Sent #{size} bytes so far"
      end
      write_string(@client, nil)
      @logger.debug "  -> Done"
    end
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

Bootstrap.new.start
