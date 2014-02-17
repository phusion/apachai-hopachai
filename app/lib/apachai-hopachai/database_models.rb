require 'rails'
require 'active_record/railtie'
Bundler.require(:default, :models)
require 'active_record/migration'
require_relative 'safe_yaml'
require_relative '../apachai-hopachai'

# Some gems don't initialize properly when used with Rails. Fix this.
DefaultValueFor.initialize_active_record_extensions
require "#{ApachaiHopachai::APP_ROOT}/webui/config/initializers/devise"

config = YAML.load_file(ApachaiHopachai::DATABASE_CONFIG_FILE)
rails_env = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
ActiveRecord::Base.logger = ApachaiHopachai.default_logger
ActiveRecord::Base.establish_connection(config[rails_env])
ActiveRecord::Migration.check_pending!

# Load models.
Dir["#{ApachaiHopachai::MODELS_DIR}/*.rb"].each do |filename|
  filename = filename.sub(/\.rb$/, '')
  require(filename)
end
