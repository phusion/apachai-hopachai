require 'shellwords'

class BuildsController < ApplicationController
  skip_before_action :verify_authenticity_token, :only => :create
  skip_before_filter :authenticate_user!, :only => :create
  before_filter :fetch_project
  before_filter :authorize_project
  before_filter :fetch_build, :except => [:index, :create]

  include CustomUrlHelper

  def index
    @builds = @project.job_sets
  end

  def create
    respond_to do |format|
      format.html do
        verify_authenticity_token
        return if performed?
        authenticate_user!
        return if performed?
        BuildWorker.perform_async(params)
        redirect_to project_model_path(@project, :wait_for_build => 1)
      end
      format.json do
        if check_webhook_key
          BuildWorker.perform_async(params)
        else
          render :status => 403
        end
      end
    end
  end

  def show
    begin
      authorize! :read, @build
    rescue CanCan::AccessDenied
      logger.warn "Access denied to build."
      render_build_not_found
      return
    end
  end

private
  def check_webhook_key
    params[:webhook_key] == @project.webhook_key
  end
end
