# frozen_string_literal: true

# Jobs as story rewards: a campaign can open with only some of the world's
# jobs, and the GM grants the rest as the story goes.
module Campaign::JobRewards
  extend ActiveSupport::Concern

  included do
    validate :open_jobs_are_the_worlds
  end

  # The jobs characters can take in this campaign: every job, unless the GM
  # opened only some (open_jobs) and grants the rest as the story goes.
  def available_jobs
    jobs = world.jobs.alphabetical
    open_jobs.nil? ? jobs : jobs.where(slug: open_jobs)
  end

  def job_open?(job)
    open_jobs.nil? || open_jobs.include?(job.slug)
  end

  def locked_jobs
    open_jobs.nil? ? world.jobs.none : world.jobs.alphabetical.where.not(slug: open_jobs)
  end

  # The GM grants an archetype, as a story reward, with a line for the
  # moment ("The Wind Crystal shatters"). To the party: it opens, and the
  # table sees a card for it. To someone: they awaken to it, taking it up at
  # once (it opens if it wasn't), and the table stops for it (the awakening
  # card: their face turns over, and the archetype is on the other side).
  def grant_job!(job, to: nil, line: nil)
    raise Refusal, "#{job.name} isn't one of #{world.name}'s archetypes" unless job.world_id == world_id
    raise Refusal, "#{to.name} isn't in this party" if to && to.campaign_id != id
    raise Refusal, "#{to.name} is a #{job.name} already" if to&.job_id == job.id
    raise Refusal, "#{job.name} is open already" if !to && job_open?(job)

    line = line.to_s.strip.presence
    transaction do
      update!(open_jobs: open_jobs + [ job.slug ]) unless job_open?(job)
      if to
        to.change_job!(job)
        narrate([ line, "#{to.name} awakens: #{job.name}." ].compact.join(" "), cue: "awakening",
                data: { "character" => to.id, "name" => to.name, "job" => job.name, "description" => job.description.to_s, "line" => line }.compact)
      else
        narrate([ line, "New archetype: #{job.name}." ].compact.join(" "), cue: "jobs",
                data: { "jobs" => [ { "name" => job.name, "slug" => job.slug, "description" => job.description.to_s } ] })
      end
    end
  end

  # Jobs picked at the start, or on edit: a list of slugs, all the world's,
  # or nil for every one (the form's "every job" box).
  def open_jobs=(slugs)
    super(slugs.nil? ? nil : Array(slugs).map(&:to_s).compact_blank.uniq)
  end

  private

  def open_jobs_are_the_worlds
    return if open_jobs.nil?

    unknown = open_jobs - world.jobs.pluck(:slug)
    errors.add(:open_jobs, "aren't #{world.name}'s: #{unknown.join(', ')}") if unknown.any?
  end
end
