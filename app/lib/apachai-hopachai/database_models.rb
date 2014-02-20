require 'rails'
require 'active_record/railtie'
require 'action_mailer/railtie'
Bundler.require(:default, :models)
require 'active_record/migration'
require 'erb'
require_relative 'safe_yaml'
require_relative '../apachai-hopachai'

# Some gems don't initialize properly when used with Rails. Fix this.
DefaultValueFor.initialize_active_record_extensions
require "#{ApachaiHopachai::APP_ROOT}/webui/config/initializers/devise"
Sidekiq.hook_rails!

config_data = ERB.new(File.read(ApachaiHopachai::DATABASE_CONFIG_FILE)).result
config = YAML.load(config_data, :safe => true)
rails_env = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
ActiveRecord::Base.logger = ApachaiHopachai.default_logger
ActiveRecord::Base.establish_connection(config[rails_env])
ActiveRecord::Migration.check_pending!

# Load models.
Dir["#{ApachaiHopachai::MODELS_DIR}/*.rb"].each do |filename|
  filename = filename.sub(/\.rb$/, '')
  require(filename)
end
