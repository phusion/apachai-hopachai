require 'apachai-hopachai/command_utils'
require 'apachai-hopachai/jobset_utils'

module ApachaiHopachai
  class DaemonCommand < Command
    include CommandUtils
    include JobsetUtils

    def self.description
      "Watch a queue directory and process incoming jobs"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def self.require_libs
      JobsetUtils.require_libs
      require 'apachai-hopachai/run_command'
      require 'apachai-hopachai/finalize_command'
      require 'safe_yaml'
      require 'fileutils'
      RunCommand.require_libs
      FinalizeCommand.require_libs
    end

    def start
      parse_argv
      maybe_set_log_file
      maybe_daemonize
      @logger.info "Apachai Hopachai daemon started"
      begin_watching_queue_dir
      begin
        trap_signals
        begin
          @done = false
          while !@done
            while !@done && process_eligible_jobsets > 0
              # Loop until there are no eligile jobsets.
            end
            @done ||= wait_for_queue_dir_change
          end
        ensure
          untrap_signals
        end
      ensure
        end_watching_queue_dir
      end
      @logger.info "Apachai Hopachai daemon exited"
    end

    private

    def option_parser
      require 'optparse'
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa daemon [OPTIONS] QUEUE_PATH"
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--daemonize", "-d", "Daemonize into background") do
          @options[:daemonize] = true
        end
        opts.on("--log-file FILENAME", "-l", String, "Log to the given file") do |val|
          @options[:log_file] = val
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
        self.class.help
        exit 0
      end
      if @argv.size != 1
        self.class.help
        exit 1
      end
      if @options[:daemonize] && !@options[:log_file]
        abort "If you set --daemonize then you must also set --log-file."
      end

      @queue_path = File.expand_path(@argv[0])
    end

    def begin_watching_queue_dir
      @watch = {}
      @watch[:terminator] = IO.pipe

      a, b = IO.pipe
      begin
        @watch[:pid] = Process.spawn("setsid", "inotifywait", "-m",
          "-e", "attrib,move,create,delete", "--", @queue_path,
          :in  => ['/dev/null', 'r'],
          :out => b,
          :err => b,
          :close_others => true)
      rescue Exception
        a.close
        raise
      ensure
        b.close
      end

      @watch[:io] = a
      read_until_blocks(@watch[:io])
    end

    def end_watching_queue_dir
      @watch[:io].close
      Process.kill('TERM', @watch[:pid]) rescue nil
      Process.waitpid(@watch[:pid]) rescue nil
      @watch[:terminator].each do |io|
        io.close if !io.closed?
      end
    end

    def trap_signals
      times = 0

      block = lambda do |*args|
        begin
          times += 1
          if times < 3
            STDERR.puts "Gracefully exiting (send signal #{3 - times} more times to force termination)..."
            @done = true
            begin
              @watch[:terminator][1].write_nonblock('x')
            rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EINTR
            end
          else
            STDERR.puts "Aborting!"
            exit!(1)
          end
        rescue Exception => e
          STDERR.puts "*** Exception in signal handler! #{e} (#{e.class})\n" +
            e.backtrace.join("\n")
          exit!(1)
        end
      end

      trap("TERM", &block)
      trap("INT", &block)
    end

    def untrap_signals
      trap("TERM", 'DEFAULT')
      trap("TERM", 'DEFAULT')
    end

    def wait_for_queue_dir_change
      @logger.debug "Watching for relevant filesystem changes"
      ios = select([@watch[:io], @watch[:terminator][0]])
      if ios[0].include?(@watch[:terminator][0])
        @logger.debug "Termination signal received, breaking out of main loop"
        true
      else
        @logger.debug "Filesystem changed!"
        read_until_blocks(@watch[:io])
        false
      end
    end

    def process_eligible_jobsets
      jobsets = []
      i = 0

      list_jobsets(@queue_path).each do |jobset|
        @logger.debug "Candidate: #{jobset.path}"
        if jobset.complete?
          @logger.debug "  -> Jobset is complete"
          if jobset.version_supported?
            if jobset.processing?
              @logger.debug "  -> Jobset is already being processed"
              @logger.debug "  -> Dropped"
            else
              @logger.debug "  -> Jobset is not being processed"
              @logger.debug "  -> Accepted"
              jobsets << jobset
            end
          else
            @logger.debug "  -> Jobset version #{jobset.version} not supported"
            @logger.debug "  -> Dropped"
          end
        else
          @logger.debug "  -> Jobset not complete"
          @logger.debug "  -> Dropped"
        end
        i += 1
      end
      @logger.debug "Found #{i} candidates, #{jobsets.size} are eligible for processing"

      jobsets.each do |jobset|
        if jobset.processed?
          delete_jobset(jobset)
        else
          process_jobset(jobset)
        end
      end

      jobsets.size
    end

    def delete_jobset(jobset)
      @logger.info "Deleting jobset #{jobset.path}"
      FileUtils.remove_entry_secure(jobset.path)
    end

    def process_jobset(jobset)
      @logger.info "Processing jobset #{jobset.path} with #{jobset.jobs.size} jobs"

      jobset.jobs.each do |job|
        @logger.info "Processing job #{job.path}: #{job.info['env_name']}"
        command = RunCommand.new([
          "--dry-run-test",
          "--",
          job.path
        ])
        command.logger = @logger
        command.start
      end

      @logger.info "Finalizing jobset #{jobset.path}"
      command = FinalizeCommand.new([
        "--email=hongli@phusion.nl",
        "--email-from=hongli@phusion.nl",
        "--",
        jobset.path
      ])
      command.logger = @logger
      command.start

      delete_jobset(jobset)
    end

    def read_until_blocks(io)
      while true
        begin
          io.read_nonblock(1024)
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EINTR
          break
        rescue EOFError
          abort "inotifywatch aborted unexpectedly!"
        end
      end
    end
  end
end
