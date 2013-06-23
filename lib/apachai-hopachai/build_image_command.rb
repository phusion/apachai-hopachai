# encoding: utf-8
module ApachaiHopachai
  class BuildImageCommand < Command
    def self.description
      "Build the container image"
    end

    def self.help
      puts "Usage: appa build-image"
      puts "Builds the container image."
    end

    def start
      @logger.info("Starting 'docker build'")
      system("docker", "build", RESOURCES_DIR) || exit(1)
      @logger.info("Committing image")
      container = `docker ps -a | sed -n 2p | awk '{ print $1 }'`.strip
      system("docker commit #{container} apachai-hopachai") || exit(1)
    end
  end
end