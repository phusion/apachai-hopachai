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

desc "Upload sandbox image to Docker registry"
task :release_app => :build do
  version = `./dade/scripts/dump.rb Dadefile | grep DADEFILE_VERSION | sed 's/.*=//'`.strip
  sh "docker tag phusion/apachai-hopachai:#{version}.dev phusion/apachai-hopachai:#{version}"
  sh "docker tag phusion/apachai-hopachai:#{version} phusion/apachai-hopachai:latest"
  sh "docker push phusion/apachai-hopachai"
end

desc "Run the application container"
task :run do
  sh "./dade/bin/dade run"
end

desc "Login to the container"
task :shell do
  lxc_attach("cd /app/webui && exec setuser app bash")
end

desc "Login to the container"
task :root_shell do
  lxc_attach("cd /app/webui && exec bash")
end

desc "Start an irb console for the web app"
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
