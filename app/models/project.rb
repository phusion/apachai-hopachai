require 'openssl'

class Project < ActiveRecord::Base
  has_many :job_sets, :inverse_of => :project
  belongs_to :owner, :class_name => 'User', :inverse_of => :projects

  validates :public_key, :private_key, :presence => true, :unless => :new_record?

  before_create :generate_key_pair

private
  def generate_key_pair
    key = OpenSSL::PKey::RSA.new(2048)
    self.private_key = key.to_pem
    self.public_key = key.public_key.to_pem
  end
end
