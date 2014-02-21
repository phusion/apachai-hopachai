require 'shellwords'

class BuildsController < ApplicationController
  skip_before_action :verify_authenticity_token, :only => :create
  skip_before_filter :authenticate_user!, :only => :create
  before_filter :fetch_repo
  before_filter :authorize_repo
  before_filter :fetch_build, :except => [:index, :create]
  before_filter :authorize_build, :except => [:index, :create]

  include CustomUrlHelper

  def index
    @builds = @repo.builds
  end

  def create
    respond_to do |format|
      format.html do
        verify_authenticity_token
        return if performed?

        authenticate_user!
        return if performed?

        authorize! :create_build, @repo
        BuildWorker.perform_async(@repo.id, params)
        redirect_to repo_model_path(@repo, :wait_for_build => 1)
      end
      format.json do
        authorize! :create_build, @repo
        if check_webhook_key
          BuildWorker.perform_async(params)
        else
          render :status => 403
        end
      end
    end
  end

  def show
    render
  end

private
  def check_webhook_key
    params[:webhook_key] == @repo.webhook_key
  end
end
