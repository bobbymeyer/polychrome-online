Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "worlds#index"

  # Each book is a resource namespace inside its world (docs/HANDOFF.md §7).
  resources :worlds, param: :slug, except: :destroy do
    namespace :bestiary do
      resources :monsters, param: :slug
    end
    namespace :compendium do
      resources :jobs, param: :slug
    end
    namespace :grimoire do
      resources :abilities, param: :slug
    end
    namespace :armory do
      resources :items, param: :slug
    end
  end
end
