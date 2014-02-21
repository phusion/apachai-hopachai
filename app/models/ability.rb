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

    can :manage, [Repo, Build, Job], :owner_id => user.id

    can :read, Repo do |repo|
      repo.authorizations.exists?(:user_id => user.id)
    end

    can :read, Build do |build|
      can?(:read, build.repo)
    end
    can :manage, Build do |build|
      can?(:manage, build.repo)
    end

    can :read, Job do |job|
      can?(:read, job.build.repo)
    end
    can :manage, Job do |job|
      can?(:manage, job.build.repo)
    end
  end
end
