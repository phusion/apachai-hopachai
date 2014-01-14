require 'json'
require 'safe_yaml'
require 'rbconfig'
require 'shellwords'

ROOT   = File.expand_path(File.dirname(__FILE__) + "/..")
MYDIR  = File.expand_path(File.dirname(__FILE__))
ENV['PATH'] = "#{ROOT}/bin:#{ENV['PATH']}"

def find_config
  candidates = [ENV['CONFIG_FILE'], "#{MYDIR}/config.yml", "/etc/apachai-hopachai.yml"]
  candidates.compact.each do |filename|
    if File.exist?(filename)
      return filename
    end
  end
  abort "No configuration file found. Please create /etc/apachai-hopachai.yml. See #{MYDIR}/config.yml.example for an example."
end

def ruby_exe
  if defined?(PhusionPassenger)
    if PhusionPassenger.respond_to?(:require_passenger_lib)
      PhusionPassenger.require_passenger_lib 'platform_info/ruby'
    else
      require 'phusion_passenger/platform_info/ruby'
    end
    PhusionPassenger::PlatformInfo.ruby_command
  else
    RbConfig::CONFIG['bindir'] + '/' + RbConfig::CONFIG['RUBY_INSTALL_NAME'] +
      RbConfig::CONFIG['EXEEXT']
  end
end

CONFIG = YAML.load_file(find_config, :safe => true)

app = lambda do |env|
  input = JSON.parse(env['rack.input'].read)

  command = Shellwords.join([
    "nice", ruby_exe, "-S", "appa", "prepare",
    input['repository']['url'],
    input['after'],
    "--output-dir", CONFIG['queue_dir'],
    "--repo-name", input['repository']['name'],
    "--before-sha", input['before']
  ])
puts command
  IO.popen("at now", "w") do |io|
    io.puts command
  end

  [200, { "Content-Type" => "text/plain" }, ["ok\n"]]
end

run app
