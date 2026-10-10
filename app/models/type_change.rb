# frozen_string_literal: true

# A world's types, changed as a whole (the types editor): renamed, recoloured,
# added, removed, re-charted. The setting can go from sixteen types to one
# or to thirty.
#
# A removed type's uses go where the author sends them: spells and items
# that dealt it, monsters and jobs that were it, terrain that had it. A
# monster's own affinity with a removed type is dropped, not moved (a
# Goblin weak to Fire mustn't become weak to everything when Fire folds
# into Normal); what was dropped is reported so it can be put back.
# Battles already running keep the chart they started with.
class TypeChange
  attr_reader :world, :rows, :sends, :terrain, :moved, :dropped

  # rows: the new TypeChart rows, in order (the first is plain).
  # sends: { removed slug => slug it goes to } for every removed type.
  # terrain: { place => slug }, optional.
  def initialize(world, rows:, sends: {}, terrain: nil)
    @world = world
    @rows = rows
    @sends = sends.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    @terrain = terrain
    @moved = Hash.new { |h, k| h[k] = [] }
    @dropped = []
    @before = world.type_chart
    @removed = @before.slugs - TypeChart.new(rows).slugs
  end

  # What uses each type now: { slug => ["Fire (spell)", "Bomb (monster)", ...] }.
  def self.uses(world)
    uses = Hash.new { |h, k| h[k] = [] }
    world.abilities.alphabetical.each do |ability|
      ability.effects.filter_map { |e| e["type"] }.uniq.each { |type| uses[type] << ability.name }
    end
    world.items.alphabetical.each do |item|
      Array(item.effects).filter_map { |e| e["type"] }.uniq.each { |type| uses[type] << item.name }
    end
    world.monsters.alphabetical.each do |monster|
      uses[monster.base_type] << monster.name
      uses[monster.second_type] << monster.name if monster.second_type
      monster.affinities.each_key { |type| uses[type] << "#{monster.name}'s affinity" }
    end
    world.jobs.alphabetical.each { |job| uses[job.base_type] << job.name }
    world.terrain_types.each { |place, type| uses[type] << "#{place.capitalize} terrain" }
    uses
  end

  # The types going, and their names as they were.
  attr_reader :removed, :before

  # Apply it all, or nothing. Returns false with the world's errors set
  # when the new types don't make a chart.
  def save
    new_slugs = TypeChart.new(rows).slugs
    bad = removed.reject { |type| new_slugs.include?(sends[type]) }
    bad.each { |type| world.errors.add(:damage_types, "#{before.name(type)} is being removed: pick a type for its uses to go to") }
    return false if bad.any?

    world.transaction do
      world.damage_types = rows.map { |row| row.merge("against" => row.fetch("against", {}).slice(*new_slugs)) }
      world.terrain_types = (terrain || world.terrain_types).to_h.transform_values { |type| send_to(type) }
      raise ActiveRecord::Rollback unless world.save

      move_books
    end
    world.errors.empty?
  end

  private

  def send_to(type)
    removed.include?(type) ? sends.fetch(type) : type
  end

  # Entries are rewritten with update_columns: the types they name have
  # just changed under them, so this is the one place they can't be
  # validated one at a time against the world.
  def move_books
    world.abilities.each { |ability| retype_effects(ability) }
    world.items.each { |item| retype_effects(item) }
    world.monsters.each do |monster|
      changes = {}
      changes[:base_type] = send_to(monster.base_type) if removed.include?(monster.base_type)
      if monster.second_type && removed.include?(monster.second_type)
        second = send_to(monster.second_type)
        changes[:second_type] = second == changes.fetch(:base_type, monster.base_type) ? nil : second
      end
      lost = monster.affinities.slice(*removed)
      if lost.any?
        changes[:affinities] = monster.affinities.except(*removed)
        lost.each { |type, affinity| dropped << "#{monster.name}: #{affinity} #{before.name(type)}" }
      end
      next if changes.empty?

      moved[changes[:base_type]] << monster.name if changes[:base_type]
      monster.update_columns(changes)
    end
    world.jobs.each do |job|
      next unless removed.include?(job.base_type)

      moved[send_to(job.base_type)] << job.name
      job.update_columns(base_type: send_to(job.base_type))
    end
  end

  def retype_effects(entry)
    effects = Array(entry.effects)
    return unless effects.any? { |e| removed.include?(e["type"]) }

    moved[send_to(effects.find { |e| removed.include?(e["type"]) }["type"])] << entry.name
    entry.update_columns(effects: effects.map { |e| removed.include?(e["type"]) ? e.merge("type" => send_to(e["type"])) : e })
  end
end
