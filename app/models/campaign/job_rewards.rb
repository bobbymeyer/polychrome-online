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

  # The GM grants jobs, with a line for the moment ("The Wind Crystal
  # shatters"). The table sees a card for each.
  def grant_jobs!(jobs, line = nil)
    jobs = jobs.reject { |job| job_open?(job) }
    raise Refusal, "Pick a job that isn't open yet" if jobs.empty?

    transaction do
      update!(open_jobs: (open_jobs || []) + jobs.map(&:slug))
      body = [ line.to_s.strip.presence, "New #{'job'.pluralize(jobs.size)}: #{jobs.map(&:name).to_sentence}." ].compact.join(" ")
      narrate(body, cue: "jobs",
                    data: { "jobs" => jobs.map { |j| { "name" => j.name, "slug" => j.slug, "description" => j.description.to_s } } })
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
