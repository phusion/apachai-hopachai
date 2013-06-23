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
      require 'optparse'
      RunCommand.require_libs
      FinalizeCommand.require_libs
    end

    def initialize(*args)
      super(*args)
      @last_report_number = 0
    end

    def start
      parse_argv
      maybe_set_log_file
      maybe_daemonize
      maybe_create_pid_file
      begin
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
      ensure
        maybe_destroy_pid_file
      end
    end

    private

    def option_parser
      require 'apachai-hopachai/finalize_command'
      @options = {}
      @finalize_options = FinalizeCommand.default_options.dup
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa daemon [OPTIONS] QUEUE_PATH"
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--report-dir DIR", String, "Save reports to this directory instead of into the jobsets") do |val|
          @options[:report_dir] = val
        end
        opts.on("--email EMAIL", String, "Notify the given email address") do |val|
          @finalize_options[:email] = val
        end
        opts.on("--email-from EMAIL", String, "The From address for email notofications. Default: #{@finalize_options[:email_from]}") do |val|
          @finalize_options[:email_from] = val
        end
        opts.on("--email-subject STRING", String, "The subject for email notofications. Default: #{@finalize_options[:email_subject]}") do |val|
          @finalize_options[:email_subject] = val
        end
        opts.on("--dry-run-test", "Do everything except running the actual tests") do |val|
          @options[:dry_run_test] = true
        end
        opts.on("--daemonize", "-d", "Daemonize into background") do
          @options[:daemonize] = true
        end
        opts.on("--pid-file FILENAME", String, "Write PID to this file") do |val|
          @options[:pid_file] = val
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
          @options[:dry_run_test] ? "--dry-run-test" : nil,
          "--",
          job.path
        ].compact)
        command.logger = @logger
        command.start
      end

      @logger.info "Finalizing jobset #{jobset.path}"
      finalize_args = []
      @finalize_options.each_pair do |key, val|
        finalize_args << "--#{key.to_s.gsub(/_/, '-')}"
        finalize_args << val
      end
      if @options[:report_dir]
        finalize_args << "--report"
        finalize_args << next_report_filename
        finalize_args << "--format-report-filename"
      end
      command = FinalizeCommand.new([finalize_args, "--", jobset.path].flatten)
      command.logger = @logger
      command.start

      delete_jobset(jobset)
    end

    def next_report_filename
      now = Time.now.strftime("%Y-%m-%d-%H:%M:%S")
      if @last_report_time == now
        @last_report_number += 1
        "#{@options[:report_dir]}/appa-report-#{now}-#{@last_report_number}-%{status}.html"
      else
        @last_report_number = 1
        "#{@options[:report_dir]}/appa-report-#{now}-1-%{status}.html"
      end
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
