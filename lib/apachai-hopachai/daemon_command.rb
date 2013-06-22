require 'apachai-hopachai/jobset_utils'

module ApachaiHopachai
  class DaemonCommand < Command
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
      require 'tmpdir'
      require 'safe_yaml'
    end

    def start
      parse_argv
      maybe_set_log_file
      maybe_daemonize
      begin_watching_queue_dir
      begin
        while true
          process_eligible_jobsets
          wait_for_queue_dir_change
        end
      ensure
        end_watching_queue_dir
      end
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
      a, b = IO.pipe
      begin
        @watch[:pid] = Process.spawn("inotifywait", "-e", "attrib,move,create,delete", "--", @queue_path,
          :in  => ['/dev/null', 'r'],
          :out => b,
          :err => :out,
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
      Process.kill('TERM', @watch[:pid]) rescue nil
      Process.waitpid(@watch[:pid]) rescue nil
      @watch[:io].close
    end

    def wait_for_queue_dir_change
      @logger.debug "Watching for relevant filesystem changes"
      select([@watch[:io]])
      @logger.debug "Filesystem changed!"
      read_until_blocks(@watch[:io])
    end

    def process_eligible_jobsets
      jobsets = []
      i = 0

      list_jobsets(@queue_path).each |jobset|
        @logger.debug "Candidate: #{jobset.path}"
        if js.complete?
          @logger.debug "  -> Jobset is complete"
          if js.version_supported?
            if js.processed?
              @logger.debug "  -> Jobset is processed"
              @logger.debug "  -> Accepted"
              jobsets << jobset
            else
              @logger.debug "  -> Jobset not processed"
              @logger.debug "  -> Dropped"
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
      @logger.debug "Found #{i} candidates, #{jobsets.size} were eligible for processing"

      jobsets.each do |jobset|
        process_jobset(jobset)
      end
    end

    def process_jobset(jobset)
      @logger.info "Processing jobset #{jobset.path}"
    end

    def read_until_blocks(io)
      while true
        begin
          io.read_nonblock(1024)
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EINTR
          break
        end
      end
    end
  end
end
