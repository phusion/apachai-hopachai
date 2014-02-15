class Project < ActiveRecord::Base
  has_many :job_sets, :inverse_of => :project
  belongs_to :owner, :class_name => 'User', :inverse_of => :projects
end
