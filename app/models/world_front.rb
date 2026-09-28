# frozen_string_literal: true

# A setting's pressure, written once: "The Brass Syndicate's grab for the
# docks", as its clocks and the secrets behind it. Dealt into a campaign,
# it becomes that campaign's own clocks and secrets, tied to the places and
# people the campaign brought in from the atlas and cast. A clock can say
# what one of those places becomes when it fills (a mode, made there).
#
#   clocks:  [{ "name", "segments", "triggers", "full_line", "public",
#               "place_id", "mode_name", "mode_line", "mode_description" }]
#   secrets: [{ "body", "place_id", "figure_id" }]
class WorldFront < ApplicationRecord
  belongs_to :world
  has_many :dealt_clocks, class_name: "Clock", dependent: :nullify
  has_many :dealt_secrets, class_name: "Secret", dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true, uniqueness: { scope: :world_id }
  validate :has_something

  scope :in_order, -> { order(:name) }

  def clocks=(rows)
    super(Array(rows.is_a?(Hash) ? rows.values : rows).filter_map do |row|
      row = row.to_h.stringify_keys
      name = row["name"].to_s.strip
      next if name.empty?

      { "name" => name, "segments" => (row["segments"].to_i.nonzero? || 6).clamp(2, 12),
        "triggers" => Array(row["triggers"]).map(&:to_s) & Clock::TRIGGERS.keys,
        "full_line" => row["full_line"].to_s.strip.presence, "public" => ActiveModel::Type::Boolean.new.cast(row["public"]) || false,
        "place_id" => row["place_id"].presence&.to_i, "mode_name" => row["mode_name"].to_s.strip.presence,
        "mode_line" => row["mode_line"].to_s.strip.presence, "mode_description" => row["mode_description"].to_s.strip.presence }.compact
    end)
  end

  def secrets=(rows)
    super(Array(rows.is_a?(Hash) ? rows.values : rows).filter_map do |row|
      row = row.to_h.stringify_keys
      body = row["body"].to_s.strip
      { "body" => body, "place_id" => row["place_id"].presence&.to_i, "figure_id" => row["figure_id"].presence&.to_i }.compact unless body.empty?
    end)
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

  def has_something
    errors.add(:base, "A front needs a clock or a secret") if clocks.empty? && secrets.empty?
  end
end
