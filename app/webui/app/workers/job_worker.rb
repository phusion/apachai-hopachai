class JobWorker
  include Sidekiq::Worker
  sidekiq_options :queue => :jobs, :retry => false

  def perform(job_id)
    command = [
      "#{ApachaiHopachai::BIN_DIR}/appa",
      "run",
      job_id.to_s
    ]
    system(*command)
  end
end
