class Mailer < ActionMailer::Base
  default :from => ApachaiHopachai.config['email_from']

  def build_report(build_id)
    @build = JobSet.find(build_id)
    @project = @build.project
    status = @build.state.to_s.humanize
    mail(:to => @project.owner.email,
      :subject => "[#{status}] #{@project.name} (#{@build.short_revision_set})")
  end
end
