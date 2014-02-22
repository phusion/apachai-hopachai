#!/usr/bin/env ruby
require_relative './list_files'
require 'fileutils'

def copy_files(prefix, files, destination)
  if !STDOUT.tty?
    puts "Copying #{files.size} files to #{destination}"
  end
  files.each_with_index do |filename, i|
    dir = File.dirname(filename)
    if !File.exist?("#{destination}/#{dir}")
      FileUtils.mkdir_p("#{destination}/#{dir}")
    end
    if File.symlink?("#{prefix}/#{filename}")
      target = File.readlink("#{prefix}/#{filename}")
      File.symlink(target, "#{destination}/#{filename}")
    else
      FileUtils.install("#{prefix}/#{filename}", "#{destination}/#{filename}", :preserve => true)
    end
    if STDOUT.tty?
      printf "\r[%5d/%5d] [%3.0f%%] Copying files...", i + 1, files.size, i * 100.0 / files.size
      STDOUT.flush
    end
  end
  if STDOUT.tty?
    printf "\r[%5d/%5d] [%3.0f%%] Copying files...\n", files.size, files.size, 100
  end
end

if $0 == __FILE__
  prefix = ARGV.first
  files = ARGV[1 .. ARGV.size - 2]
  destination = File.absolute_path(ARGV.last)
  copy_files(prefix, files, destination)
end
