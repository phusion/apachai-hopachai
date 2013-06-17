module ApachaiHopachai
  class ShellCommand < Command
    def self.description
      "Start the container and run a shell in it"
    end

    def self.help
      puts "Usage: appa shell"
    end

    def start
      result = system("docker run -t -i -h=apachai-hopachai -u=appa -p 3002 -p 3003 " +
        "apachai-hopachai sudo -u appa /bin/bash -l")
      exit 1 if !result
    end
  end
end