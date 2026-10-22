# frozen_string_literal: true

# The seven books on a world's shelf, in the order the world's page and the masthead keep them. `key` is the book's
# route namespace; `association` is where the world keeps its entries.
module World::Books
  Book = Data.define(:title, :nav, :key, :blurb, :association) do
    def entries(world) = world.public_send(association)
    def model = World.reflect_on_association(association).klass
  end

  LIST = [
    Book.new("Bestiary", "Bestiary", :bestiary, "Monsters: stat blocks, affinities, behavior, drops.", :monsters),
    Book.new("Archetype Compendium", "Compendium", :compendium, "Archetypes: stat modifiers, equipment, learn tables.", :jobs),
    Book.new("Grimoire", "Grimoire", :grimoire, "Abilities, composed from the engine's primitives.", :abilities),
    Book.new("Armory", "Armory", :armory, "Items and equipment.", :items),
    Book.new("Encounter Tables", "Encounters", :encounters, "Weighted monster groups by terrain and tier.", :encounter_tables),
    Book.new("Gazetteer", "Gazetteer", :gazetteer, "Town and dungeon templates that locations are rolled from.", :location_templates),
    Book.new("Generator Tables", "Generators", :generation, "Names, hooks, rooms, buildings and loot for the generators.", :generator_tables)
  ].freeze

  # The book an entry is in.
  def self.for(entry) = LIST.find { |book| entry.is_a?(book.model) }
end
