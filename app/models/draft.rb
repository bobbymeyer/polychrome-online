# frozen_string_literal: true

# What the language model suggests (config/llm.yml), for the GM to keep or
# throw away. The GM asks, with an idea or none; DraftJob asks the model,
# away from the request, since a local model can take a while; the
# suggestions land on the page as they come. Nothing is used until it's kept,
# and keeping goes through the same models as writing it by hand.
#
# Each kind (Drafts::*) says what it tells the model, how it reads the
# answer and what keeping one does. owner is the campaign (prep) or the
# world (world building); target, when there is one, is what it's for (a
# location's modes, an entry's description).
class Draft < ApplicationRecord
  KINDS = %w[secrets clocks scene mode description family setting].freeze
  # waiting: the model couldn't be reached; DraftJob tries again later.
  STATUSES = %w[queued waiting running done failed].freeze

  belongs_to :owner, polymorphic: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  after_commit :broadcast, on: %i[create update]

  # A new ask replaces the last one for the same thing.
  def self.start!(owner, kind, request, target: nil)
    draft = transaction do
      where(owner: owner, kind: kind, target: gid(target)).destroy_all
      create!(owner: owner, kind: kind, target: gid(target), request: request.to_h.stringify_keys)
    end
    DraftJob.perform_later(draft)
    draft
  end

  def self.latest(owner, kind, target = nil)
    where(owner: owner, kind: kind, target: gid(target)).order(:id).last
  end

  def self.gid(record)
    record&.to_global_id&.to_s
  end

  def self.slot_id(kind, target)
    [ "draft", kind, gid(target).to_s.parameterize.presence ].compact.join("_")
  end

  def writer
    "Drafts::#{kind.camelize}".constantize.new(self)
  end

  def target_record
    target && GlobalID::Locator.locate(target)
  end

  def finished? = status.in?(%w[done failed])

  def run!(client)
    update!(status: "running")
    found = writer.items(client.json(**writer.messages))
    raise Llm::Error, "The language model suggested nothing usable" if found.empty?

    update!(status: "done", items: found)
  rescue Llm::Unreachable => e
    update!(status: "waiting", error: e.message)
    raise
  rescue Llm::Error => e
    update!(status: "failed", error: e.message)
  end

  # Keep one suggestion. Returns what the writer says happened:
  # { notice:, path: } (path: somewhere to go to finish it, if anywhere).
  def keep!(index)
    item = items.fetch(index) { raise Refusal, "There's no suggestion #{index + 1}" }
    raise Refusal, "Already kept" if item["kept"]

    result = transaction do
      writer.keep!(item).tap do
        update!(items: items.each_with_index.map { |row, i| i == index ? row.merge("kept" => true) : row })
      end
    end
    result
  end

  def slot_id = self.class.slot_id(kind, target_record)

  private

  def broadcast
    broadcast_replace_to owner, :drafts, target: slot_id, partial: "drafts/results", locals: { draft: self, kind: kind, target: target_record }
  end
end
