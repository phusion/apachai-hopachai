$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__) + "/lib"))
require 'apachai-hopachai/version'
require 'apachai-hopachai/packaging'

Gem::Specification.new do |s|
  s.name = "apachai-hopachai"
  s.version = ApachaiHopachai::VERSION_STRING
  s.summary = "Travis-like continuous integration system built on Docker"
  s.email = "software-signing@phusion.nl"
  s.homepage = "https://github.com/phusion/apachai-hopachai"
  s.description = "A simple, serverless continuous integration system that " +
    "supports Travis config files, utilizing Docker for isolation."
  s.license = "MIT"
  s.authors = ["Hongli Lai"]
  s.files = Dir[*APACHAI_HOPACHAI_FILES]
  s.add_dependency("safe_yaml")
  s.add_dependency("ansi2html")
  s.add_dependency("mail")
end
