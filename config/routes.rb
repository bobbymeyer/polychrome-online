Rails.application.routes.draw do
  # Accounts. The first one made is the admin.
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[new create]
  resources :users, only: %i[index update destroy]
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
    namespace :encounters do
      resources :encounter_tables, param: :slug, path: "tables"
    end
    namespace :gazetteer do
      resources :location_templates, param: :slug, path: "templates"
    end
    namespace :generation do
      resources :generator_tables, param: :slug, path: "tables"
    end

    # The asset pipeline (§8): the world's art direction, and generating
    # candidates for an entry's image with ComfyUI.
    resource :art_direction, only: %i[show update], path: "art"
    resources :art_batches, only: %i[create destroy], path: "art/batches"
    resource :art_panel, only: :show, path: "art/panel"
    resources :art_candidates, only: [], path: "art/candidates" do
      post :pick, on: :member
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
    resources :scenes, only: %i[new create]

    # The table (§7): the live session page with the dialogue box and log.
    resources :flags, only: %i[create update destroy] do
      post :bump, on: :member
    end
    # Every GM diff on this campaign's locations, with reverts (§7).
    resource :changes, only: :show

    resource :table, only: :show
    resource :music, only: :update, controller: "music"
    resources :checks, only: :create
    resource :forecast, only: :show
    resource :table_seat, only: %i[create destroy]
    resource :composer, only: :show
    resources :messages, only: :create

    # The pointcrawl map (§7). The side panel is a Turbo Frame; the SVG
    # updates by broadcast for every viewer.
    resource :map, only: :show
    resource :map_panel, only: :show
    resources :map_nodes, only: %i[new create], path: "map/nodes"
    resource :travel, only: :create
    resource :encounter, only: %i[create destroy]
  end

  resources :map_nodes, only: %i[edit update destroy], path: "map/nodes" do
    post :place_party, on: :member
    resources :map_edges, only: :create, path: "paths"
    resource :location, only: :create, controller: "node_locations"
  end

  # Towns and dungeons (§7). Everything but viewing is a GM control.
  resources :locations, only: %i[show update] do
    member do
      post :reroll
      post :pin
      post :unpin
      patch :stock
      patch :boss
      post :add_npc
      post :add_room
      post :enter
      post :move
      post :take_treasure
      post :revert
    end
    # A town's shop: buy from its stock, sell from the bag.
    resources :services, only: :create
    resource :shop, only: [] do
      post :buy
      post :sell
      post :sell_worn
    end
  end
  resources :map_edges, only: %i[edit update destroy], path: "map/paths"

  resources :npcs, only: %i[edit update destroy]
  resources :messages, only: :destroy
  resources :choices, only: [] do
    member do
      post :pick
      post :settle
    end
  end
  resources :scenes, only: %i[edit update destroy] do
    post :play, on: :member
  end

  resources :characters, only: %i[show edit update destroy] do
    resource :job, only: :update, controller: "character_jobs"
    resource :equipment, only: :update
    resource :ability_slots, only: :update
    resource :grant, only: :create
    resource :item_use, only: :create
  end

  # The battle screen (§6): one long-lived page fed by Turbo Streams. The
  # command panel is a Turbo Frame reloaded after each beat plays.
  resources :battles, only: :show do
    post :call_off, on: :member
    resource :seat, only: %i[create destroy]
    resource :panel, only: :show
    resources :actions, only: :create, controller: "battle_actions"
    resource :playback, only: :update
    resource :auto, only: :update, controller: "battle_autos"
  end
end
