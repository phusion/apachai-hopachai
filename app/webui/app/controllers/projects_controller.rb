class ProjectsController < ApplicationController
  before_filter :fetch_project
  before_filter :authorize_project

  include CustomUrlHelper

  def show
    if latest_build = @project.builds.first
      redirect_to build_model_path(latest_build)
    else
      @wait_for_build = params[:wait_for_build]
    end
  end

  def settings
    render
  end

  def destroy
    @project.destroy
    redirect_to root_path, :notice => "Project #{@project.long_name} deleted."
  end

private
  def authorize_project(authorization = :write)
    super(authorization)
  end
end
