Rails.application.routes.draw do
  # Accounts. The first one made is the admin.
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[new create]
  resources :users, only: %i[index update destroy]
  # Where the language model is (SiteSetting), for admins.
  resource :settings, only: %i[show update]
  get "up" => "rails/health#show", as: :rails_health_check

  root "worlds#index"

  get "types", to: redirect("/worlds/base/types") # the base world's chart, where it used to live
  get "how-to-play", to: "guides#show", as: :how_to_play
  # Local co-op: the QR code on the shared screen leads here.
  get "join/:code", to: "joins#show", as: :join
  post "join/:code", to: "joins#create"
  resources :worlds, param: :slug do
    # Each book is a resource namespace inside its world (docs/HANDOFF.md §7).
    namespace :bestiary do
      resources :monsters, param: :slug do
        resource :trial, only: :show # tried against a level-5 party (Monster::Trial)
      end
    end
    namespace :compendium do
      resources :jobs, param: :slug
    end
    namespace :grimoire do
      resources :abilities, param: :slug
      resources :families, only: %i[new create]
    end
    namespace :armory do
      resources :items, param: :slug
    end
    namespace :encounters do
      resources :encounter_tables, param: :slug, path: "tables"
    end
    namespace :gazetteer do
      resources :location_templates, param: :slug, path: "templates" do
        # What the template makes over a hundred seeds (Generators::Report).
        resource :report, only: :show, module: :location_templates
      end
    end
    namespace :generation do
      resources :generator_tables, param: :slug, path: "tables" do
        # A story table over a few hundred moments, and one to try (StoryCoverage).
        resource :coverage, only: :show, module: :generator_tables
      end
      # Every fact a story row can ask about (Campaign::Moment).
      resource :facts, only: :show
    end

    # The setting's damage types and chart, and the skills its checks use.
    scope module: :worlds do
      resource :types, only: %i[show edit update]
      resource :skills, only: %i[show edit update]
      resource :origins, only: %i[show edit update]

      # The setting's canon: its atlas, its cast, its lore.
      resources :world_places, path: "atlas", except: :show, controller: "places"
      resources :world_routes, path: "atlas/roads", only: %i[create destroy edit update], controller: "routes"
      resources :world_maps, path: "atlas/maps", only: %i[new create edit update destroy], controller: "maps" do
        resources :world_map_links, only: %i[create destroy], module: :maps, path: "beside", controller: "links"
      end
      resources :world_figures, path: "cast", except: :show, controller: "figures"
      resources :codex_entries, path: "codex"
      resources :world_fronts, path: "fronts", except: :show, controller: "fronts"
      # Its music (Track): uploaded or linked.
      resources :tracks, path: "music", except: :show
      # Its pocket history, rolled over the atlas and written into the canon.
      resource :history, only: %i[show update create destroy], controller: "histories"
    end

    # The language model's suggestions for world building (Draft).
    resources :drafts, only: %i[create destroy] do
      resources :keeps, only: :create, module: :drafts
    end

    # The campaign layer (§2): a party's run through the world.
    resources :campaigns, only: %i[new create]
  end

  resources :campaigns, only: %i[show edit update] do
    resources :characters, only: %i[new create]
    resources :battles, only: %i[new create]
    resources :npcs, only: %i[new create]
    resources :scenes, only: %i[new create]
    resources :map_nodes, only: %i[new create], path: "map/nodes"
    resources :messages, only: :create
    # The language model's suggestions for prep (Draft).
    resources :drafts, only: %i[create destroy] do
      resources :keeps, only: :create, module: :drafts
    end

    # Everything that belongs to the campaign alone (app/controllers/campaigns/).
    scope module: :campaigns do
      resources :inventories, only: %i[create update], path: "bag"

      # Prep: pressure, secrets, what's being said and done (one page).
      resource :prep, only: :show
      # Every battle's numbers together, for the GM balancing the game (Battle::Report.across).
      resource :battle_report, only: :show
      # A fight played out many times before anyone plays it (BattleSimulation).
      resource :simulation, only: :show
      resources :flags, only: %i[create update destroy] do
        resources :bumps, only: :create, module: :flags
      end
      resources :clocks, only: %i[create update destroy] do
        resources :ticks, only: :create, module: :clocks
      end
      resources :secrets, only: %i[create update destroy] do
        resource :revelation, only: %i[create destroy], module: :secrets
        # The next of its clues comes out (Secret#find_clue!).
        resources :clues, only: :create, module: :secrets
      end
      resources :rumours, only: %i[create destroy]
      resources :deeds, only: %i[create destroy]
      resource :legends, only: :show
      # The world's atlas and cast, brought into the campaign (Atlas).
      resource :canon, only: :create
      resources :front_deals, only: :create
      # Every GM diff on this campaign's locations, with reverts (§7).
      resource :changes, only: :show

      # The table (§7): the live session page with the dialogue box and log.
      resource :table, only: :show
      # After a wipe, what the story does with the party (Campaign::Defeat).
      resource :recovery, only: :create
      resource :time, only: :update
      resource :music, only: :update, controller: "music"
      resources :checks, only: :create
      resources :field_uses, only: %i[create update]
      resources :job_grants, only: :create
      resources :grants, only: :create
      resource :join_code, only: :create
      resource :forecast, only: :show
      resource :table_seat, only: %i[create destroy]
      # A seated player has the table open (heartbeat_controller): who is here.
      resource :presence, only: :update
      resource :composer, only: :show
      # What's live, for the GM to make a move from (Campaign::Moves).
      resource :moves, only: %i[show create]
      # A line or a veil for this table, from any seat, unsigned (Campaign::Limits).
      resources :limits, only: :create, path: "lines-and-veils"

      # The pointcrawl map (§7). The side panel is a Turbo Frame; the SVG
      # updates by broadcast for every viewer.
      # The campaign's maps (Map; §7): the GM's editor page (index, ?map= the one open), the setting's copies
      # and the GM's own; the panel beside it is a Turbo Frame.
      resources :maps, only: %i[index create edit update destroy] do
        resources :map_links, only: %i[create destroy], module: :maps, path: "beside"
      end
      resource :map_panel, only: :show
      # The stage's map view: a map to browse (GET), the GM putting one on the stage (PATCH).
      resource :map_view, only: %i[show update]
      # The table's controls: the GM calls talk, travel or things to do here (Campaign::Controls).
      resource :controls, only: :update
      # Where next: a player's suggestion (a vote), or the GM going (Campaign::Ways).
      resources :ways, only: :create
      resource :encounter, only: %i[create destroy]
    end
  end

  resources :map_nodes, only: %i[edit update destroy], path: "map/nodes" do
    resource :party, only: :create, module: :map_nodes
    resources :map_edges, only: :create, path: "paths"
    resource :location, only: :create, module: :map_nodes
    # Its other states (MapNode::Modes), for any place: a town, a landmark, the wilds.
    resources :modes, only: %i[create destroy], module: :map_nodes
    resource :current_mode, only: %i[update destroy], module: :map_nodes
  end

  # Towns and dungeons (§7). Everything but viewing is a GM control, each a
  # resource of its own; the shop and services are for whoever is in town.
  resources :locations, only: %i[show update] do
    scope module: :locations do
      resource :reroll, only: :create
      # A picture for one of its modes (ModeArt), uploaded by the GM.
      resources :mode_arts, only: %i[update destroy], path: "mode-pictures", param: :mode
      resource :memory, only: :destroy # the tables it was rolled from when the party came
      resources :pins, only: %i[create destroy]
      resource :stock, only: %i[update destroy]
      resource :boss, only: :update
      resources :npcs, only: :create
      resources :rooms, only: :create
      resource :entry, only: :create
      resource :position, only: :update
      resources :treasures, only: :create
      resources :reversions, only: :create
      resources :purchases, only: :create
      resources :sales, only: :create
    end
  end
  resources :map_edges, only: %i[edit update destroy], path: "map/paths"

  resources :npcs, only: %i[edit update destroy]
  resources :messages, only: :destroy do
    # The GM says a line the world offered (Campaign::Remarks).
    resource :saying, only: :create, module: :messages
  end
  resources :choices, only: [] do
    scope module: :choices do
      resources :picks, only: :create
      resource :settlement, only: :create
    end
  end
  resources :scenes, only: %i[edit update destroy] do
    resource :play, only: %i[create update destroy], module: :scenes
    resources :beats, only: :create
  end
  # A scene's beats (Beat): the sequencer on the scene's page.
  resources :beats, only: %i[update destroy] do
    scope module: :beats do
      resource :move, only: :create
      resource :copy, only: :create
    end
  end

  resources :characters, only: %i[show edit update destroy] do
    scope module: :characters do
      resource :job, only: :update
      resource :equipment, only: :update, controller: "equipment"
      resource :ability_slots, only: :update
      resource :item_use, only: :create
      resource :chest, only: :update # taking from and putting into the party's chest
    end
  end

  # The battle screen (§6): one long-lived page fed by Turbo Streams. The
  # command panel is a Turbo Frame reloaded after each beat plays.
  resources :battles, only: :show do
    scope module: :battles do
      resource :call_off, only: :create
      resource :seat, only: %i[create destroy]
      resource :panel, only: :show
      resources :actions, only: :create
      resource :playback, only: :update
      resource :auto, only: :update
      # A player's page has the battle in front of them (BattleRecord#arrive!).
      resource :arrival, only: :create
      # Someone has the battle open: its clock runs (BattleRecord#watch!).
      resource :watch, only: :update
      # Its numbers, for the GM balancing it (Battle::Report).
      resource :report, only: :show
    end
  end
end
