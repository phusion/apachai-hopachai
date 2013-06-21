require 'json'
require 'safe_yaml'
require 'rbconfig'

abort "Please set the CONFIG_FILE environment variable" if !ENV['CONFIG_FILE']
CONFIG = YAML.load_file(ENV['CONFIG_FILE'], :safe => true)
ROOT   = File.expand_path(File.dirname(__FILE__) + "/..")

def slug(title)
  title.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
end

def ruby_exe
  RbConfig::CONFIG['bindir'] + '/' + RbConfig::CONFIG['RUBY_INSTALL_NAME'] +
    RbConfig::CONFIG['EXEEXT']
end

app = lambda do |env|
  input      = JSON.parse(env['rack.input'].read)
  time_str   = Time.now.strftime("%Y-%m-%d-%H:%M:%S")
  output_dir = CONFIG['report_dir'] + "/" + slug(input['repository']['name'])
  report     = "#{output_dir}/#{time_str}.html"
  log        = "#{output_dir}/#{time_str}.log"

  Dir.mkdir(output_dir)
  result = system(ruby_exe, "#{ROOT}/bin/appa", "run",
    input['repository']['url'],
    input['after'],
    "--report", report,
    "--email", CONFIG['email'],
    "--daemonize",
    "--log-file", log)
  if result
    [200, { "Content-Type" => "text/plain" }, ["ok\n"]]
  else
    [500, { "Content-Type" => "text/plain" }, ["error\n"]]
  end
end

run app
