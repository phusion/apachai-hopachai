ApachaiHopachai::Application.routes.draw do
  root :to => "home#index"
  devise_for :users, :controllers => {:registrations => "registrations"}
  ActiveAdmin.routes(self)
  resources :users
end