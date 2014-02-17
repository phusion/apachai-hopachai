class Authorization < ActiveRecord::Base
  belongs_to :project, :inverse_of => :authorizations
  belongs_to :user, :inverse_of => :authorizations

  validates :project_id, :user_id, :presence => true
end
