# encoding: utf-8

module ApachaiHopachai
  class SetupSymlinksCommand < Command
    def self.description
      "Setup system symlinks"
    end

    def self.help
      puts "Usage: appa setup-symlinks"
      puts "Setup system symlinks."
    end

    def start
      if File.symlink?(WEBAPP_SYMLINK)
        @logger.info "Removing symlink #{WEBAPP_SYMLINK}"
        File.unlink(WEBAPP_SYMLINK)
      end
      @logger.info "Creating symlink #{WEBAPP_SYMLINK} pointing to #{WEBAPP_DIR}"
      File.symlink(WEBAPP_DIR, WEBAPP_SYMLINK)
    end
  end
end