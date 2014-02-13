# encoding: utf-8

module ApachaiHopachai
  module JobsetUtils
    def self.require_libs
      require 'safe_yaml'
    end

    class Jobset
      attr_reader :path

      def initialize(path)
        @path = path
      end

      def info
        @info ||= YAML.load_file("#{@path}/info.yml", :safe => true)
      end

      def jobs
        Dir["#{@path}/*.appa-job"].map { |path| Job.new(path) }
      end

      # Returns whether a jobset directory is complete, i.e.
      # it's not still being written to by 'appa prepare'.
      def complete?
        File.exist?("#{@path}/info.yml")
      end

      def version
        info['file_version']
      end

      def version_supported?
        version == '1.0'
      end

      def processing?
        jobs.any? { |job| job.processing? }
      end

      # Returns whether a jobset directory is done being
      # processed by 'run'.
      def processed?
        jobs.all? { |job| job.processed? }
      end

      def finalized?
        File.exist?("#{@path}/finalized")
      end
    end

    class Job
      attr_reader :path

      def initialize(path)
        @path = path
      end

      def info
        @info ||= YAML.load_file("#{@path}/info.yml", :safe => true)
      end

      def valid?
        @path =~ /\.appa-job$/ && File.exist?("#{@path}/info.yml")
      end

      # Returns whether this job directory is currently being
      # processed by an 'appa run' command.
      def processing?
        File.exist?("#{@path}/processing")
      end

      # Returns whether this job directory is done being
      # processed by an 'appa run' command.
      def processed?
        File.exist?("#{@path}/result.yml")
      end

      def set_processing
        File.open("#{@path}/processing", "w").close
      end

      def unset_processing
        File.unlink("#{@path}/processing")
      end

      def <=>(other)
        @info['id'] <=> other.info['id']
      end
    end

    def self.require_libs
      require 'safe_yaml'
    end

    private

    def list_jobsets(queue_path)
      Dir["#{queue_path}/*.appa-jobset"].map { |path| Jobset.new(path) }
    end
  end
end