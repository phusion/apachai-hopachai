class User < ActiveRecord::Base
  has_many :projects, :foreign_key => :owner_id, :inverse_of => :owner, :dependent => :destroy
  has_many :authorizations, :inverse_of => :user
  has_many :authorized_projects, :through => :authorizations, :source => :project, :class_name => 'Project'

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable
end
