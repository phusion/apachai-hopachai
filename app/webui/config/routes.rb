ApachaiHopachai::Application.routes.draw do
  root :to => "home#index"
  devise_for :users, :controllers => { :registrations => "registrations" }
  ActiveAdmin.routes(self)

  get    "projects/:project_owner/:project_name(.:format)" => "projects#show", :as => "project"
  get    "projects/:project_owner/:project_name/settings(.:format)" => "projects#settings", :as => "project_settings"
  put    "projects/:project_owner/:project_name/settings(.:format)" => "projects#update_settings"
  delete "projects/:project_owner/:project_name/settings(.:format)" => "projects#destroy"
  get    "projects/:project_owner/:project_name/builds(.:format)" => "builds#index", :as => "project_builds"
  post   "projects/:project_owner/:project_name/builds(.:format)" => "builds#create"
  get    "projects/:project_owner/:project_name/builds/:build_number(.:format)" => "builds#show", :as => "build"
  get    "projects/:project_owner/:project_name/builds/:build_number/jobs/:job_number(.:format)" => "jobs#show", :as => "job"

  resources :users
end