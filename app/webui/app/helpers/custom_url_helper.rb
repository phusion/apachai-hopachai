module CustomUrlHelper
private
  def project_model_path(project, *args)
    project_path(project.owner.username, project.name, *args)
  end

  def project_model_builds_path(project, *args)
    project_builds_path(project.owner.username, project.name, *args)
  end

  def project_model_settings_path(project, *args)
    project_settings_path(project.owner.username, project.name, *args)
  end

  def build_model_path(build, *args)
    build_path(build.owner.username, build.project.name, build.number, *args)
  end

  def job_model_path(job, *args)
    job_path(job.owner.username, job.project.name, job.job_set.number, job.number, *args)
  end
end
