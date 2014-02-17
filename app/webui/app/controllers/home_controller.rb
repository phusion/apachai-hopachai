class HomeController < ApplicationController
  skip_authorization_check :only => :index

  def index
    @projects = Project.accessible_by(current_ability, :read)
  end
end
