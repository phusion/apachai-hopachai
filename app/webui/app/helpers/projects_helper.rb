module ProjectsHelper
  def project_model_path(project, *args)
    project_path(project.owner.username, project.name, *args)
  end

  def project_model_builds_path(project, *args)
    project_builds_path(project.owner.username, project.name, *args)
  end

  def project_model_settings_path(project, *args)
    project_settings_path(project.owner.username, project.name, *args)
  end
end
