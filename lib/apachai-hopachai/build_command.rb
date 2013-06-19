module ApachaiHopachai
  class BuildCommand < Command
    def self.description
      "Build the container image"
    end

    def self.help
      puts "Usage: appa build"
      puts "Builds the container image."
    end

    def start
      @logger.info("Starting 'docker build'")
      system("docker build src") || exit(1)
      @logger.info("Committing image")
      container = `docker ps -a | sed -n 2p | awk '{ print $1 }'`.strip
      system("docker commit #{container} apachai-hopachai") || exit(1)
    end
  end
end