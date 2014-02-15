# Setup ActiveRecord.
require 'active_record'
require 'active_record/base'
require 'active_record/migration'

ActiveRecord::Base.establish_connection
ActiveRecord::Migration.check_pending!

# Load models.
Dir["#{ApachaiHopachai::APP_ROOT}/*.rb"].each do |filename|
  filename = filename.sub(/\.rb$/, '')
  require(filename)
end
