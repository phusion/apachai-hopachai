class Authorization < ActiveRecord::Base
  belongs_to :repo, :inverse_of => :authorizations
  belongs_to :user, :inverse_of => :authorizations

  validates :repo_id, :user_id, :presence => true
end
