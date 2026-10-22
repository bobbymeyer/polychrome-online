# frozen_string_literal: true

# What a world's books leave loose, for the person building them: a book with nothing in it, a table of encounters with no
# groups, an archetype that teaches nothing, a creature no road meets. Only what is certainly unfinished is said, and
# nothing here is wrong: a boss is placed by hand, a form is met through another entry, a summon is called by an ability.
class World::LooseEnds
  Item = Data.define(:summary, :book, :records)

  def initialize(world)
    @world = world
  end

  def items
    @items ||= [ *empty_books, *tables_without_groups, *archetypes_teaching_nothing, *monsters_on_no_road ]
  end

  delegate :none?, :any?, to: :items

  private

  attr_reader :world

  def book(key) = World::Books::LIST.find { |book| book.key == key }

  def empty_books
    World::Books::LIST.reject { |book| book.entries(world).exists? }.map do |book|
      Item.new("The #{book.title} has no entries yet.", book, [])
    end
  end

  def tables_without_groups
    empty = world.encounter_tables.select { |table| table.entries.empty? }
    empty.any? ? [ Item.new("Encounter tables with no monster groups", book(:encounters), empty) ] : []
  end

  def archetypes_teaching_nothing
    bare = world.jobs.where.missing(:job_levels).order(:name).to_a
    bare.any? ? [ Item.new("Archetypes that teach nothing", book(:compendium), bare) ] : []
  end

  # Not a boss (placed by hand), not a form another entry becomes, not called by an ability, not in a table's groups.
  def monsters_on_no_road
    monsters = world.monsters.alphabetical.to_a
    met = world.encounter_tables.flat_map { |table| table.entries.flat_map { |group| group["monsters"].keys } }
    forms = monsters.flat_map { |monster| monster.phases.map { |phase| phase["becomes"] } }
    summoned = world.abilities.flat_map { |ability| Array(ability.effects).filter_map { |effect| effect["creature"] if effect["primitive"] == "summon" } }
    placed = met + forms + summoned
    loose = monsters.reject { |monster| monster.boss? || placed.include?(monster.slug) }
    loose.any? && world.encounter_tables.exists? ? [ Item.new("Monsters no encounter table sends against the party", book(:bestiary), loose) ] : []
  end
end
