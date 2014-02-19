class JobLogsController < ApplicationController
  before_filter :fetch_project
  before_filter :authorize_project
  before_filter :fetch_build
  before_filter :authorize_build
  before_filter :fetch_job
  before_filter :authorize_job

  include ActionController::Live

  def show
    headers["Content-Type"] = "text/event-stream"
    begin
      if @job.state == :processing
        stream_log_file_until_job_processed
      else
        render_log_file
      end
    ensure
      response.stream.close
    end
  end

private
  def render_log_file
    File.open(@job.log_file_path, "rb") do |f|
      while !f.eof?
        response.stream.write("data: #{f.readline}\n")
      end
    end
  end

  def stream_log_file_until_job_processed
    tail_file(@job.log_file_path) do |pid, io|
      cancellator = IO.pipe
      begin
        # While streaming, watch for changes on the job status. If the status
        # changes then we abort the connection after 2 seconds.
        thread = spawn_thread do
          done = false
          while !done
            if IO.select([cancellator[0]], nil, nil, 5)
              # Cancellation requested: maybe client disconnected.
              done = true
            else
              begin
                @job.reload
                @job.check_really_processing!
                if @job.state != :processing
                  logger.debug("Job #{@job.long_number} state has changed. Canceling log stream.")
                  done = true
                  if !IO.select([cancellator[0]], nil, nil, 2)
                    begin
                      Process.kill('TERM', pid)
                    rescue Errno::EPERM, Errno::ESRCH
                    end
                  end
                end
              rescue ActiveRecord::StaleObjectError
                # Ignore error, try again later.
              end
            end
          end
        end

        # Stream log file until `tail` is terminated or until
        # the client is gone.
        while true
          begin
            if line = timed_readline(io, 30)
              response.stream.write("data: #{line}\n")
            else
              # Check whether connection is still alive every 30 sec.
              response.stream.write("event: ping\n")
            end
          rescue IOError, EOFError, Errno::EPIPE, Errno::ECONNRESET
            logger.debug("Stopping streaming of log.")
            break
          end
        end

        true
      ensure
        cancellator[1].close if !cancellator[1].closed?
        thread.join if thread
        cancellator[0].close if !cancellator[0].closed?
      end
    end
  end

  def tail_file(filename)
    begin
      a, b = IO.pipe
      pid = Process.spawn("tail", "-f", "-n", "+1", filename,
        :in  => ["/dev/null", "r"],
        :out => b,
        :err => :err,
        :close_others => true)
      b.close
      a.binmode
      done = yield(pid, a)
    ensure
      a.close if a && !a.closed?
      b.close if b && !b.closed?
      Process.kill('TERM', pid) if pid && !done
      begin
        Process.waitpid(pid)
      rescue Errno::EPERM, Errno::ESRCH, Errno::ECHILD
      end
    end
  end

  def timed_readline(io, timeout)
    if IO.select([io], nil, nil, timeout)
      io.readline.force_encoding('utf-8').scrub
    else
      nil
    end
  end

  def spawn_thread
    Thread.new do
      begin
        yield
      rescue Exception => e
        Rails.logger.error("#{e} (#{e.class})\n  " << e.backtrace.join("\n  "))
      end
    end
  end
end