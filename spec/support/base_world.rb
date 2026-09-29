# frozen_string_literal: true

# The base world, built once for the whole suite rather than for every
# example: building it takes about a second, and hundreds of examples use
# it. It's built fresh at the start of each run (so it's always today's
# seeds), outside the examples' transactions, and each example's changes to
# it roll back with the example.
module BaseWorldHelper
  def base_world = World.find_by!(slug: "base")

  # The base world with its map cleared, for specs that draw their own.
  def base_world_without_atlas
    base_world.tap do |world|
      world.world_routes.destroy_all
      world.world_places.destroy_all
    end
  end
end

RSpec.configure do |config|
  config.include BaseWorldHelper

  config.before(:suite) do
    next unless defined?(Rails) && defined?(World)

    require Rails.root.join("db/seeds/base_world")
    World.where(slug: "base").destroy_all
    Seeds::BaseWorld.run
  end
end
