#!/usr/bin/env ruby
abort "This tool must be run in Ruby 1.9" if RUBY_VERSION <= '1.9'

require 'socket'
require 'gserver'

class StatusServer < GServer
  def initialize(*args)
    super(*args)
    @termination_pipe = IO.pipe
  end

  def shutdown_and_join
    shutdown
    puts "shutting down"
    @termination_pipe[1].close
    # Wake up server thread gracefully.
    Thread.new do
      TCPSocket.new('127.0.0.1', 3003).close
    end
    join
    @termination_pipe[0].close
  end

  def serve(io)
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
  def initialize(argv)
    @argv = argv.dup
  end

  def start
    start_status_server
    begin
      exit(execute_app)
    ensure
      stop_status_server
    end
  end

  private

  def start_status_server
    @server = StatusServer.new(3003, '0.0.0.0')
    @server.start
  end

  def stop_status_server
    @server.shutdown_and_join
  end

  def execute_app
    system("./main", *@argv)
    if $?
      $?.exitstatus
    else
      1
    end
  end
end

Runner.new(ARGV).start
