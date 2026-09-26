Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "worlds#index"

  resources :worlds, param: :slug, except: :destroy do
    # Each book is a resource namespace inside its world (docs/HANDOFF.md §7).
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

    # The campaign layer (§2): a party's run through the world.
    resources :campaigns, only: %i[new create]
  end

  resources :campaigns, only: %i[show edit update] do
    resources :characters, only: %i[new create]
    resources :battles, only: %i[new create]
    resources :inventories, only: %i[create update], path: "bag"
    resource :rest, only: :create
    resources :npcs, only: %i[new create]

    # The table (§7): the live session page with the dialogue box and log.
    resource :table, only: :show
    resource :table_seat, only: %i[create destroy]
    resource :composer, only: :show
    resources :messages, only: :create
  end

  resources :npcs, only: %i[edit update destroy]

  resources :characters, only: %i[show edit update destroy] do
    resource :job, only: :update, controller: "character_jobs"
    resource :equipment, only: :update
    resource :ability_slots, only: :update
    resource :grant, only: :create
  end

  # The battle screen (§6): one long-lived page fed by Turbo Streams. The
  # command panel is a Turbo Frame reloaded after each beat plays.
  resources :battles, only: :show do
    resource :seat, only: %i[create destroy]
    resource :panel, only: :show
    resources :actions, only: :create, controller: "battle_actions"
    resource :playback, only: :update
  end
end
