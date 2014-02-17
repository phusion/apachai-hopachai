class Ability
  include CanCan::Ability

  attr_reader :user

  def initialize(user)
    return nil if user.nil?
    @user = user

    # Define abilities for the passed in user here. For example:
    #
    #   user ||= User.new # guest user (not logged in)
    #   if user.admin?
    #     can :manage, :all
    #   else
    #     can :read, :all
    #   end
    #
    # The first argument to `can` is the action you are giving the user permission to do.
    # If you pass :manage it will apply to every action. Other common actions here are
    # :read, :create, :update and :destroy.
    #
    # The second argument is the resource the user can perform the action on. If you pass
    # :all it will apply to every resource. Otherwise pass a Ruby class of the resource.
    #
    # The third argument is an optional hash of conditions to further filter the objects.
    # For example, here the user can only update published articles.
    #
    #   can :update, Article, :published => true
    #
    # See the wiki for details: https://github.com/ryanb/cancan/wiki/Defining-Abilities
    
    if user.admin?
      can :manage, :all
      can :read, ActiveAdmin::Page, :name => "Dashboard"
      return
    end

    can :manage, [Project, JobSet, Job], :owner_id => user.id

    can :read, Project do |project|
      project.authorizations.exists?(:user_id => user.id)
    end

    can :read, JobSet do |job_set|
      can?(:read, job_set.project)
    end
    can :manage, JobSet do |job_set|
      can?(:manage, job_set.project)
    end

    can :read, Job do |job|
      can?(:read, job.job_set.project)
    end
    can :manage, Job do |job|
      can?(:manage, job.job_set.project)
    end
  end
end
