Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "worlds#index"

  # The battle screen (§6): one long-lived page fed by Turbo Streams. The
  # command panel is a Turbo Frame reloaded after each beat plays.
  resources :battles, only: :show do
    resource :seat, only: %i[create destroy]
    resource :panel, only: :show
    resources :actions, only: :create, controller: "battle_actions"
    resource :playback, only: :update
  end

  # Each book is a resource namespace inside its world (docs/HANDOFF.md §7).
  resources :worlds, param: :slug, except: :destroy do
    resources :battles, only: %i[index new create], shallow: true
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
