require 'json'
require 'safe_yaml'
require 'rbconfig'
require 'shellwords'

abort "Please set the CONFIG_FILE environment variable" if !ENV['CONFIG_FILE']
CONFIG = YAML.load_file(ENV['CONFIG_FILE'], :safe => true)
ROOT   = File.expand_path(File.dirname(__FILE__) + "/..")

def ruby_exe
  if defined?(PhusionPassenger)
    require 'phusion_passenger/platform_info/ruby'
    PhusionPassenger::PlatformInfo.ruby_command
  else
    RbConfig::CONFIG['bindir'] + '/' + RbConfig::CONFIG['RUBY_INSTALL_NAME'] +
      RbConfig::CONFIG['EXEEXT']
  end
end

app = lambda do |env|
  input      = JSON.parse(env['rack.input'].read)
  time_str   = Time.now.strftime("%Y-%m-%d-%H:%M:%S")

  command = Shellwords.join([ruby_exe, "appa", "prepare",
    input['repository']['url'], input['after'],
    "--output-dir", CONFIG['queue_dir']])
  IO.pipe("at now", "w") do |io|
    io.puts command
  end

  [200, { "Content-Type" => "text/plain" }, ["ok\n"]]
end

run app
