# encoding: utf-8
module ApachaiHopachai
  VERSION_STRING     = '1.0.0'
  APP_ROOT           = File.expand_path(File.dirname(__FILE__) + "/..")
  RESOURCES_DIR      = "#{APP_ROOT}/resources"
  SANDBOX_IMAGE_NAME = "phusion/apachai-hopachai-sandbox"
  SUPERVISOR_COMMAND = "/usr/local/rvm/bin/rvm-exec ruby-2.1.0 ruby /appa/bin/supervisor"
  SANDBOX_JOB_RUNNER_COMMAND = "sudo -u appa -H /usr/local/rvm/bin/rvm-exec 2.1.0 ruby /appa/bin/job_runner"
end
