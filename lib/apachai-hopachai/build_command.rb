module ApachaiHopachai
  class BuildCommand < Command
    def self.description
      "Build the container"
    end

    def start
      @logger.level = Logger::INFO
      @logger.info("Starting 'docker build'")
      system("docker build src") || exit(1)
      @logger.info("Committing image")
      container = `docker ps -a | sed -n 2p | awk '{ print $1 }'`.strip
      system("docker commit #{container} apachai-hopachai") || exit(1)
    end
  end
end