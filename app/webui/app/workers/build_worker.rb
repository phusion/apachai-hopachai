require 'tmpdir'

class BuildWorker
  include Sidekiq::Worker
  sidekiq_options :queue => :builds, :retry => 5

  def perform(project_id, params)
    project = Project.find(project_id)
    Dir.mktmpdir do |path|
      command = [
        "#{ApachaiHopachai::BIN_DIR}/appa",
        "prepare",
        project.long_name
      ]
      head_sha = params['after'] || params['head']
      if head_sha
        command << head_sha
      end
      if params['before']
        command << "--before-sha"
        command << params['before']
      end
      command << "--id-file"
      command << "#{path}/id.txt"

      if system(*command)
        build_id = File.read("#{path}/id.txt")
        build = JobSet.find(build_id)
        build.jobs.each do |job|
          JobWorker.perform_async(job.id)
        end
      end
    end
  end
end