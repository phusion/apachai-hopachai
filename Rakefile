desc "Build the sandbox"
task :sandbox do
  sh "docker build --rm -t phusion/apachai-hopachai-sandbox sandbox"
end

desc "Upload sandbox image to Docker registry"
task :release_sandbox do
  sh "docker push phusion/apachai-hopachai-sandbox"
end

desc "Build the application container"
task :build do
  sh "./dade/bin/dade build"
end

desc "Run the application container"
task :run do
  sh "./dade/bin/dade run"
end

desc "Login to the container"
task :shell do
  lxc_attach("exec bash")
end

task :irb do
  lxc_attach("cd /app/webui && exec setuser app ./bin/rails console")
end

def lxc_attach(command)
  require 'shellwords'
  subcommand = ". /etc/container_environment.sh && #{command}"
  puts "Running in container: #{command}"
  exec "sudo lxc-attach -n #{read_cid} -- /bin/sh -c #{Shellwords.escape subcommand}"
end

def read_cid
  if File.exist?(".dade_container")
    File.read(".dade_container").strip
  else
    abort "Container not running."
  end
end
