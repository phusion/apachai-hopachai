class JobsController < ApplicationController
  before_filter :fetch_repo
  before_filter :authorize_repo
  before_filter :fetch_build
  before_filter :authorize_build
  before_filter :fetch_job
  before_filter :authorize_job

  def show
    begin
      authorize! :read, @repo
    rescue CanCan::AccessDenied
      logger.warn "Access denied to repo."
      render_repo_not_found
      return
    end
    begin
      authorize! :read, @build
    rescue CanCan::AccessDenied
      logger.warn "Access denied to build."
      render_build_not_found
      return
    end
    begin
      authorize! :read, @job
    rescue CanCan::AccessDenied
      logger.warn "Access denied to job."
      render_job_not_found
    end

    @job.check_really_processing!
  end
end
