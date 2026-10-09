# frozen_string_literal: true

# Book entries in a package (PackageArchive): how an entry is written, and
# how a world takes them back. A campaign module carries the entries it
# uses (CampaignModule::Books); a world package carries all of them
# (WorldPackage). Entries name each other by slug, so they travel as they
# are; the few ids (a template's table, a job's levels) go by slug too.
module PackageBooks
  KINDS = {
    "abilities" => :abilities, "items" => :items, "monsters" => :monsters, "encounter_tables" => :encounter_tables,
    "generator_tables" => :generator_tables, "location_templates" => :location_templates, "jobs" => :jobs
  }.freeze
  # What isn't the entry's own: its row in this database.
  SKIP = %w[id world_id created_at updated_at encounter_table_id].freeze
  # A monster's script and forms name moves and other monsters that may
  # not be in the world yet: they go on once everything else is.
  LATER = %w[ai_script phases].freeze

  module_function

  # An entry as a package writes it: its columns, less what's this database's.
  def attributes(entry)
    attrs = entry.attributes.except(*SKIP)
    attrs["encounter_table"] = entry.encounter_table&.slug if entry.is_a?(LocationTemplate)
    attrs["levels"] = entry.job_levels.includes(:ability).order(:level, :id).map { |level| [ level.ability.slug, level.level ] } if entry.is_a?(Job)
    attrs
  end

  # The entries a world doesn't have yet, from { kind => [row, ...] }, saved
  # as their references allow, pass after pass, with their pictures.
  # Monsters go in without their scripts and forms, which follow once
  # every move and creature is in. Refuses, naming what wouldn't go in, if
  # some never do. Returns how many were added.
  def add!(world, books, archive, from:)
    rows = KINDS.flat_map do |kind, scope|
      have = world.public_send(scope).pluck(:slug)
      Array(books.is_a?(Hash) ? books[kind] : nil).select { |row| row.is_a?(Hash) && row["slug"].is_a?(String) && !have.include?(row["slug"]) }
                                                    .map { |row| [ scope, row ] }
    end
    pending = rows.dup
    made = {}
    loop do
      saved = pending.select { |scope, row| (made[row] = save(world, scope, row, archive)) }
      pending -= saved
      break if pending.empty? || saved.empty?
    end
    if pending.any?
      problems = pending.first(5).map do |scope, row|
        entry = build(world, scope, row)
        entry.valid?
        "#{entry.name.presence || row['slug']}: #{entry.errors.full_messages.to_sentence}"
      end
      raise Refusal, "#{world.name} can't take some of #{from}'s book entries: #{problems.join('; ')}."
    end

    rows.each do |scope, row|
      next unless scope == :monsters && (row.keys & LATER).any?

      # The same object that was saved: a second copy of the row would take its picture's
      # upload, which waits for the commit, away from it.
      monster = made.fetch(row)
      next if monster.update(row.slice(*LATER))

      raise Refusal, "#{world.name} can't take #{monster.name}'s script or forms from #{from}: #{monster.errors.full_messages.to_sentence}."
    end
    rows.size
  end

  # The entry, saved, or nil if it won't save yet.
  def save(world, scope, row, archive)
    entry = build(world, scope, row)
    return unless entry.save

    if entry.is_a?(Job)
      Array(row["levels"]).each do |slug, level|
        ability = world.abilities.find_by(slug: slug) or next
        entry.job_levels.create!(ability: ability, level: JsonCasting.integer(level).to_i.clamp(1, 100))
      end
    end
    archive.attach(entry.image, row["image"])
    entry
  end

  # Built apart from the world's own list of them, so an entry that won't save yet isn't left in it.
  def build(world, scope, row)
    model = world.public_send(scope).klass
    attrs = row.slice(*(model.column_names - SKIP))
    attrs = attrs.merge("ai_script" => [], "phases" => []) if scope == :monsters
    attrs["encounter_table"] = world.encounter_tables.find_by(slug: row["encounter_table"]) if scope == :location_templates && row["encounter_table"]
    model.new(attrs.merge("world" => world))
  end
end
