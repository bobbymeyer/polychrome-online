# frozen_string_literal: true

# A setting's pressure, written once: "The Brass Syndicate's grab for the
# docks", as its clocks and the secrets behind it (FrontClock,
# FrontSecret). Dealt into a campaign, it becomes that campaign's own
# clocks and secrets, tied to the places and people the campaign brought in
# from the atlas and cast. A clock can say what one of those places becomes
# when it fills (a mode, made there).
class WorldFront < ApplicationRecord
  belongs_to :world
  has_many :clocks, -> { order(:id) }, class_name: "FrontClock", dependent: :destroy, autosave: true, inverse_of: :world_front
  has_many :secrets, -> { order(:id) }, class_name: "FrontSecret", dependent: :destroy, autosave: true, inverse_of: :world_front
  has_many :dealt_clocks, class_name: "Clock", dependent: :nullify
  has_many :dealt_secrets, class_name: "Secret", dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true, uniqueness: { scope: :world_id }
  validate :has_something

  scope :in_order, -> { order(:name) }

  # From the form's rows (or plain hashes): the clocks it has now. The old
  # ones go when the front is saved, so a front that doesn't save keeps them.
  #   { "name", "segments", "triggers", "full_line", "public", "place_id",
  #     "mode_name", "mode_line", "mode_description" }
  def clocks=(rows)
    clocks.each(&:mark_for_destruction)
    rows_from(rows).each do |row|
      next if row["name"].to_s.strip.empty?

      clocks.build(row.slice("name", "full_line", "mode_name", "mode_line", "mode_description", "triggers")
                      .merge("segments" => (row["segments"].to_i.nonzero? || 6).clamp(2, 12), "public" => ActiveModel::Type::Boolean.new.cast(row["public"]) || false,
                             "place_id" => row["place_id"].presence))
    end
  end

  #   { "body", "place_id", "figure_id" }
  def secrets=(rows)
    secrets.each(&:mark_for_destruction)
    rows_from(rows).each do |row|
      next if row["body"].to_s.strip.empty?

      secrets.build(body: row["body"], place_id: row["place_id"].presence, figure_id: row["figure_id"].presence)
    end
  end

  def dealt_into?(campaign)
    campaign.clocks.exists?(world_front_id: id) || campaign.secrets.exists?(world_front_id: id)
  end

  # Its clocks and secrets, made the campaign's. Places and people it names
  # are linked if the campaign has them (Atlas); a clock's mode is made on
  # its place's location when there is one.
  def deal!(campaign)
    raise Refusal, "#{name} is already in #{campaign.name}" if dealt_into?(campaign)

    nodes = campaign.map_nodes.where.not(world_place_id: nil).includes(:location).index_by(&:world_place_id)
    npcs = campaign.npcs.where.not(world_figure_id: nil).index_by(&:world_figure_id)
    transaction do
      clocks.each do |row|
        location = nodes[row["place_id"]]&.location
        mode = add_mode(location, row) if location && row["mode_name"]
        campaign.clocks.create!(name: row["name"], segments: row["segments"], triggers: row["triggers"], full_line: row["full_line"],
                                public: row["public"], location_mode: mode, world_front: self)
      end
      secrets.each do |row|
        campaign.secrets.create!(body: row["body"], location: nodes[row["place_id"]]&.location, npc: npcs[row["figure_id"]], world_front: self)
      end
    end
  end

  private

  # The place's mode by that name, made if it hasn't one yet.
  def add_mode(location, row)
    location.modes.find_by(key: row["mode_name"].parameterize(separator: "_")) ||
      location.add_mode!("name" => row["mode_name"], "line" => row["mode_line"], "description" => row["mode_description"])
  end

  def rows_from(rows)
    Array(rows.is_a?(Hash) ? rows.values : rows).map { |row| row.to_h.stringify_keys }
  end

  def has_something
    kept = ->(rows) { rows.reject(&:marked_for_destruction?) }
    errors.add(:base, "A front needs a clock or a secret") if kept.(clocks).empty? && kept.(secrets).empty?
  end
end
