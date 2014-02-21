class ReposController < ApplicationController
  before_filter :fetch_repo
  before_filter :authorize_repo

  include CustomUrlHelper

  def show
    if latest_build = @repo.builds.first
      redirect_to build_model_path(latest_build)
    else
      @wait_for_build = params[:wait_for_build]
    end
  end

  def settings
    render
  end

  def destroy
    @repo.destroy
    redirect_to root_path, :notice => "Repository #{@repo.long_name} deleted."
  end

private
  def authorize_repo(authorization = :write)
    super(authorization)
  end
end
