class Mailer < ActionMailer::Base
  default :from => ApachaiHopachai.config['email_from']

  def build_report(build_id)
    @build = Build.find(build_id)
    @repo = @build.repo
    status = @build.state.to_s.humanize
    mail(:to => @repo.owner.email,
      :subject => "[#{status}] #{@repo.name} (#{@build.short_revision_set})")
  end
end
