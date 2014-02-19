class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery :with => :exception
  before_filter :authenticate_user!, :unless => :devise_or_active_admin_controller?
  check_authorization :unless => :devise_or_active_admin_controller?

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to root_path, :alert => exception.message
  end

private
  def fetch_project
    long_name = "#{params[:project_owner]}/#{params[:project_name]}"
    @project = Project.find_by_long_name(long_name)
    if !@project
      render_project_not_found
    end
  end

  def fetch_build
    @build = @project.job_sets.find_by(:number => params[:build_number])
    if !@build
      render_build_not_found
    end
  end

  def authorize_project(authorization = :read)
    begin
      authorize!(authorization, @project)
      true
    rescue CanCan::AccessDenied
      logger.warn "Access denied to project."
      render_project_not_found
      false
    end
  end

  def render_project_not_found
    respond_to do |format|
      format.html { render :template => 'projects/not_found.html', :status => 400 }
      format.json { render :template => 'projects/not_found.json', :status => 400 }
    end
  end

  def render_build_not_found
    respond_to do |format|
      format.html { render :template => 'builds/not_found.html', :status => 400 }
      format.json { render :template => 'builds/not_found.json', :status => 400 }
    end
  end

  # For ActiveAdmin.
  def access_denied(exception)
    redirect_to root_path, :alert => exception.message
  end

  def devise_or_active_admin_controller?
    devise_controller? || request.path =~ /^\/admin($|\/)/
  end
end
