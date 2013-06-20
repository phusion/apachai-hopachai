$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + "/lib"))
require 'daemon_controller/version'
require 'daemon_controller/packaging'

Gem::Specification.new do |s|
  s.name = "apachai-hopachai"
  s.version = ApachaiHopachai::VERSION_STRING
  s.summary = "..."
  s.email = "software-signing@phusion.nl"
  s.homepage = "https://github.com/phusion/apachai-hopachai"
  s.description = "..."
  s.license = "MIT"
  s.authors = ["Hongli Lai"]
  s.files = Dir[*APACHAI_HOPACHAI_FILES]
  s.add_dependency("safe_yaml")
  s.add_dependency("semaphore")
end
