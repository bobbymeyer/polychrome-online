# frozen_string_literal: true

# A stand-in for characters until build step 4. A party member is a name
# and a job at a fixed base stat line, auto-equipped with the best gear the
# job can use from the Armory.
class QuickParty
  BASE_STATS = { max_hp: 150, max_mp: 30, str: 12, mag: 12, vit: 12, spr: 12, agi: 12 }.freeze

  def initialize(world)
    @world = world
    @gear = world.items.reject(&:consumable?)
  end

  # members: [{ name: "Bartz", job: "knight" }, ...]
  def build(members)
    jobs = @world.jobs.includes(job_levels: :ability).index_by(&:slug)
    members.each_with_index.map do |member, i|
      job = jobs.fetch(member[:job].to_s) { raise ActiveRecord::RecordNotFound, "no job #{member[:job]}" }
      member_spec(member[:name].presence || job.name, job, i)
    end
  end

  private

  def member_spec(name, job, index)
    equipment = best_gear(job)
    {
      "id" => "#{name.parameterize(separator: '_').presence || 'hero'}_#{index + 1}",
      "name" => name,
      "stats" => Stats::Derivation.derive(base: BASE_STATS, job: job.to_derivation,
                                          equipment: equipment.map(&:to_equipment), passives: job.passives),
      "abilities" => job.job_levels.map { |level| level.ability.slug },
      "image" => { "book" => "jobs", "slug" => job.slug }
    }
  end

  # Per slot, the equippable item with the largest total bonus.
  def best_gear(job)
    @gear.select { |item| job.equips?(item) }.group_by(&:slot).values.map do |items|
      items.max_by { |item| [ item.stats.values.sum, item.price ] }
    end
  end
end
