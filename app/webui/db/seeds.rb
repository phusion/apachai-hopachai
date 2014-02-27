# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

if User.count == 0
  puts "Creating admin user"
  User.create!(
    :username => 'admin',
    :email => 'admin@example.com',
    :admin => true,
    :password => 'password',
    :password_confirmation => 'password')
end
if Rails.env.development? && Repo.count == 0
  passenger = Repo.create!(:owner => User.find_by(:username => 'admin'),
    :name => 'passenger',
    :url => 'https://github.com/phusion/passenger.git')
  guest = User.create!(
    :username => 'guest',
    :email => 'guest@example.com',
    :password => 'password',
    :password_confirmation => 'password')
  collaborator = User.create!(
    :username => 'collaborator',
    :email => 'collaborator@example.com',
    :password => 'password',
    :password_confirmation => 'password')
  passenger.authorizations.create!(:user => collaborator)
end
