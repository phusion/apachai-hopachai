class JobSet < ActiveRecord::Base
  has_many :jobs, :inverse_of => :job_set
  belongs_to :project, :inverse_of => :job_sets

  as_enum :state, [:unprocessed, :processing, :processed, :finalized], :strings => true, :slim => true

  default_value_for :state, :unprocessed

  validates :state, :as_enum => true
end
