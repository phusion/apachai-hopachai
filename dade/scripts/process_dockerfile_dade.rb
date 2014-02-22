#!/usr/bin/env ruby
DADEROOT = File.absolute_path(File.dirname(__FILE__) + "/..")

def process_dockerfile_dade(filename, app_dir_container_build_path)
  snippet = "ADD #{app_dir_container_build_path} /app\n"
  snippet << "ADD _dade_integration /var/lib/dade_integration\n"
  snippet << "RUN if test -e /var/lib/dade_integration/build; then /var/lib/dade_integration/build; fi\n"

  contents = File.open(filename, "r:utf-8") { |f| f.read }
  if contents =~ /^[ \t]*FROM[ \t].*/
    end_index = $~.end(0)
  else
    end_index = 0
  end
  contents[end_index..end_index] = "\n#{snippet}\n"
  contents
end

puts process_dockerfile_dade(ARGV[0], ARGV[1])
