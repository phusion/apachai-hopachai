#!/usr/bin/env ruby
require_relative './list_files'
require 'fileutils'

def copy_files(name, prefix, destination, files)
  if !STDOUT.tty?
    puts "Copying #{name} (#{files.size}) to #{destination}"
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
      printf "\r[%5d/%5d] [%3.0f%%] Copying #{name}", i + 1, files.size, i * 100.0 / files.size
      STDOUT.flush
    end
  end
  if STDOUT.tty?
    printf "\r[%5d/%5d] [%3.0f%%] Copying #{name}\n", files.size, files.size, 100
  end
end

if $0 == __FILE__
  name        = ARGV[0]
  prefix      = ARGV[1]
  destination = File.absolute_path(ARGV[2])
  files       = ARGV[3 .. -1]
  copy_files(name, prefix, destination, files)
end
