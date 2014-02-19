class JobsController < ApplicationController
  before_filter :fetch_project
  before_filter :fetch_build
  before_filter :fetch_job

  def show
    begin
      authorize! :read, @project
    rescue CanCan::AccessDenied
      logger.warn "Access denied to project."
      render_project_not_found
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

private
  def fetch_job
    @job = @build.jobs.find_by(:number => params[:job_number])
    if !@job
      render_job_not_found
    end
  end

  def render_job_not_found
    respond_to do |format|
      format.html { render :template => 'jobs/not_found.html', :status => 400 }
      format.json { render :template => 'jobs/not_found.json', :status => 400 }
    end
  end
end
