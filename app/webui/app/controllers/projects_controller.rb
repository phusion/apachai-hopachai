class ProjectsController < ApplicationController
  before_filter :fetch_project

  include CustomUrlHelper

  def show
    begin
      authorize! :read, @project
    rescue CanCan::AccessDenied
      logger.warn "Access denied to project."
      render_project_not_found
      return
    end

    if latest_build = @project.job_sets.first
      redirect_to build_model_path(latest_build)
    else
      @wait_for_build = params[:wait_for_build]
    end
  end
end
