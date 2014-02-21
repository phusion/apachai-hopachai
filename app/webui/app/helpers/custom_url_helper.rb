module CustomUrlHelper
private
  def repo_model_path(repo, *args)
    repo_path(repo.owner.username, repo.name, *args)
  end

  def repo_model_builds_path(repo, *args)
    repo_builds_path(repo.owner.username, repo.name, *args)
  end

  def repo_model_settings_path(repo, *args)
    repo_settings_path(repo.owner.username, repo.name, *args)
  end

  def build_model_path(build, *args)
    build_path(build.owner.username, build.repo.name, build.number, *args)
  end

  def job_model_path(job, *args)
    job_path(job.owner.username, job.repo.name, job.build.number, job.number, *args)
  end
end
