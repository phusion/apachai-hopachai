#!/usr/bin/env ruby

def process_dockerfile_dade(filename, app_dir_container_build_path)
  contents = File.open(filename, "r:utf-8") { |f| f.read }
  if contents =~ /^[ \t]*FROM[ \t].*/
    end_index = $~.end(0)
  else
    end_index = 0
  end
  contents[end_index..end_index] = "\nADD #{app_dir_container_build_path} /app\n"
  contents
end

puts process_dockerfile_dade(ARGV[0], ARGV[1])
