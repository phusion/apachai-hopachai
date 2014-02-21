class User < ActiveRecord::Base
  has_many :repos, :foreign_key => :owner_id, :inverse_of => :owner, :dependent => :destroy
  has_many :authorizations, :inverse_of => :user
  has_many :authorized_repos, :through => :authorizations, :source => :repo, :class_name => 'Repo'

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable
end
