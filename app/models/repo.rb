require 'openssl'
require 'securerandom'
require 'tmpdir'

class Repo < ActiveRecord::Base
  has_many :builds, -> { order("number DESC") },
    :inverse_of => :repo, :dependent => :destroy
  has_many :authorizations, :inverse_of => :repo
  belongs_to :owner, :class_name => 'User', :inverse_of => :repos

  default_value_for(:webhook_key) { SecureRandom.hex(32) }

  validates :owner_id, :name, :url, :presence => true
  validates :public_key, :private_key, :presence => true, :unless => :new_record?

  before_create :generate_key_pairs

  def self.find_by_long_name(long_name)
    owner, name = long_name.split("/", 2)
    raise ArgumentError, "Invalid owner name" if owner.blank?
    raise ArgumentError, "Invalid repository name" if name.blank?
    user = User.where(:username => owner).first
    if user
      user.repos.where(:name => name).first
    else
      nil
    end
  end

  def self.accessible_by(ability, authorization)
    user = ability.user
    if user.admin?
      Repo.all
    else
      if authorization != :read
        admin_sql = "AND admin"
      end
      Repo.from(%Q{
        (
          (
            SELECT * FROM repos WHERE owner_id = #{user.id}
          ) UNION (
            SELECT repos.* FROM repos
            LEFT JOIN authorizations ON repos.id = authorizations.repo_id
            WHERE authorizations.user_id = #{user.id}
            #{admin_sql}
          )
        ) AS repos
      })
    end
  end

  def long_name
    "#{owner.username}/#{name}"
  end

  def as_json(options = nil)
    if options.nil? || options.empty?
      options = { :only => [:long_name, :name, :url, :public_key, :created_at] }
    end
    super(options)
  end

private
  def generate_key_pairs
    key = OpenSSL::PKey::RSA.new(4096)
    Dir.mktmpdir do |path|
      pid = Process.spawn("ssh-keygen", "-C", "apachai-hopachai", "-b", "4096", "-f", "#{path}/key",
        :in  => ["/dev/null", "r"],
        :out => :out,
        :err => :err,
        :close_others => true)
      Process.waitpid(pid)
      if $?.exitstatus != 0
        raise "Cannot generate SSH keys."
      end
      self.private_ssh_key = File.read("#{path}/key")
      self.public_ssh_key = File.read("#{path}/key.pub")
    end
    self.private_key = key.to_pem
    self.public_key = key.public_key.to_pem
  end
end
