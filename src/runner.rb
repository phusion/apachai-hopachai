#!/usr/bin/env ruby
abort "This tool must be run in Ruby 1.9" if RUBY_VERSION <= '1.9'
STDOUT.sync = STDERR.sync = true

require 'socket'
require 'gserver'
require 'thread'
require 'logger'
require 'base64'

PORT = 3003

class StatusServer < GServer
  attr_reader :notify, :clients_accepted

  def initialize(*args)
    super(*args)
    @termination_pipe = IO.pipe
    @notify = {
      :mutex => Mutex.new,
      :cond => ConditionVariable.new
    }
    @clients_accepted = 0
  end

  def shutdown_and_join
    shutdown
    @termination_pipe[1].close
    # Wake up server thread gracefully.
    Thread.new do
      TCPSocket.new('127.0.0.1', port).close
    end
    join
    @termination_pipe[0].close
  end

  def serve(io)
    Thread.current.abort_on_exception = true
    @notify[:mutex].synchronize do
      @clients_accepted += 1
      @notify[:cond].broadcast
    end

    io.puts "You have control"

    a, b = IO.pipe
    pid = Process.spawn("tail", "-f", "--pid=#{$$}", "--bytes=+0", "output/runner.log",
      :in  => :in,
      :out => b,
      :err => b,
      :close_others => true)
    b.close
    
    begin
      io.binmode
      a.binmode

      while true
        ios = select([a, @termination_pipe[0]])[0]
        if ios.include?(a)
          begin
            buf = a.readpartial(1024 * 32)
          rescue EOFError
            break
          end
          io.write(buf)
        else
          break
        end
      end
    ensure
      Process.kill('TERM', pid)
      Process.waitpid(pid)
    end
  end
end

class Runner
  def initialize(config)
    @config = Marshal.load(Base64.decode64(config))
    @argv   = @config[:args]
    @logger = Logger.new(STDOUT)
    @logger.level = @config[:log_level]
    @logger.info "Runner started with config: #{@config.inspect}"
  end

  def start
    start_status_server
    wait_for_first_status_server_client
    begin
      exit(execute_app)
    ensure
      stop_status_server
    end
  end

  private

  def start_status_server
    @logger.info "Starting status server on port #{PORT}"
    @server = StatusServer.new(PORT, '0.0.0.0')
    @server.start
  end

  def wait_for_first_status_server_client
    @logger.info "Waiting for host to connect to the status server"
    @server.notify[:mutex].synchronize do
      while @server.clients_accepted == 0
        @server.notify[:cond].wait(@server.notify[:mutex])
      end
    end
    @logger.info "Host connected to status server!"
  end

  def stop_status_server
    @logger.info "Shutting down status server"
    @server.shutdown_and_join
    @logger.info "Status server shut down"
  end

  def execute_app
    @logger.info "Executing ./main #{@argv.join(' ')}"
    system("./main", *@argv)
    if $?
      $?.exitstatus
    else
      1
    end
  end
end

Runner.new(ARGV[0]).start
