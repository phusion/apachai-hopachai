class HomeController < ApplicationController
  skip_authorization_check :only => :index

  def index
    @repos = Repo.accessible_by(current_ability, :read)
  end
end
