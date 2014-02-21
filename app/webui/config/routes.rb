require 'sidekiq/web'

ApachaiHopachai::Application.routes.draw do
  root :to => "home#index"
  devise_for :users, :controllers => { :registrations => "registrations" }
  ActiveAdmin.routes(self)

  get    "repos/:repo_owner/:repo_name(.:format)" => "repos#show", :as => "repo"
  delete "repos/:repo_owner/:repo_name(.:format)" => "repos#destroy"
  get    "repos/:repo_owner/:repo_name/settings(.:format)" => "repos#settings", :as => "repo_settings"
  put    "repos/:repo_owner/:repo_name/settings(.:format)" => "repos#update_settings"
  get    "repos/:repo_owner/:repo_name/builds(.:format)" => "builds#index", :as => "repo_builds"
  post   "repos/:repo_owner/:repo_name/builds(.:format)" => "builds#create"
  get    "repos/:repo_owner/:repo_name/builds/:build_number(.:format)" => "builds#show", :as => "build"
  get    "repos/:repo_owner/:repo_name/builds/:build_number/jobs/:job_number(.:format)" => "jobs#show", :as => "job"
  get    "repos/:repo_owner/:repo_name/builds/:build_number/jobs/:job_number/log" => "job_logs#show", :as => "job_log"

  resources :users

  authenticate :user, lambda { |u| u.admin? } do
    mount Sidekiq::Web => '/sidekiq'
  end
end