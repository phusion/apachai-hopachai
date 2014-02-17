class BuildsController < ApplicationController
  before_filter :fetch_project
  before_filter :authorize_project
  before_filter :fetch_build, :except => :index

  def index
    @builds = @project.job_sets
  end

  def show
    begin
      authorize! :read, @build
    rescue CanCan::AccessDenied
      logger.warn "Access denied to build."
      render_build_not_found
    end
  end
end
