class ProjectsController < ApplicationController
  before_filter :fetch_project

  def show
    begin
      authorize! :read, @project
    rescue CanCan::AccessDenied
      logger.warn "Access denied to project."
      render_project_not_found
      return
    end

    @latest_build = @project.job_sets.first
    @wait_for_build = params[:wait_for_build]
  end
end
