# frozen_string_literal: true

# A world's words over the game's fixed ones: the mechanics stay, the
# setting names them. Stored in World#terms:
#
#   { "currency" => "crowns", "hp" => "Grit", "mp" => "Nerve",
#     "stats" => { "str" => "Brawn" }, "services" => { "temple" => "Surgeon" },
#     "statuses" => { "petrify" => "Rust-lock" }, "services_off" => ["temple"] }
#
# Anything not named keeps the game's word.
module World::Vocabulary
  extend ActiveSupport::Concern

  STATS = %w[str mag vit spr agi].freeze
  SERVICES = %w[inn shop guild temple].freeze
  DEFAULTS = {
    "currency" => "gil", "hp" => "HP", "mp" => "MP",
    "stats" => { "str" => "Str", "mag" => "Mag", "vit" => "Vit", "spr" => "Spr", "agi" => "Agi" },
    "services" => { "inn" => "Inn", "shop" => "Shop", "guild" => "Guild", "temple" => "Temple" }
  }.freeze

  included do
    validate :terms_are_words
  end

  # "currency", "hp", "mp", "stat.str", "service.inn", "status.poison".
  def word(key)
    World::Vocabulary.word(terms, key)
  end

  # "1,500 gil", in the world's money.
  def money(amount) = World::Vocabulary.money(terms, amount)

  def self.money(terms, amount) = "#{amount.to_i.to_fs(:delimited)} #{word(terms, 'currency')}"

  # The word from a set of terms, or the game's own when they don't say.
  def self.word(terms, key)
    group, name = key.to_s.split(".", 2)
    if name
      plural = "#{group}#{'e' if group == 'status'}s"
      terms.to_h.dig(plural, name).presence || DEFAULTS.dig(plural, name) || name.humanize
    else
      terms.to_h[group].presence || DEFAULTS.fetch(group, group.humanize)
    end
  end

  def services_off
    Array(terms["services_off"]) & SERVICES
  end

  def service_offered?(kind)
    services_off.exclude?(kind.to_s)
  end

  # From the words form: blanks dropped, so the game's word comes back.
  def terms=(value)
    value = value.to_h.deep_stringify_keys
    clean = ->(hash) { hash.to_h.transform_values { |v| v.to_s.strip }.reject { |_, v| v.empty? } }
    super({ "currency" => value["currency"].to_s.strip, "hp" => value["hp"].to_s.strip, "mp" => value["mp"].to_s.strip,
            "stats" => clean.(value["stats"]).slice(*STATS), "services" => clean.(value["services"]).slice(*SERVICES),
            "statuses" => clean.(value["statuses"]).slice(*Battle::STATUSES),
            "services_off" => Array(value["services_off"]).map(&:to_s) & SERVICES }.reject { |_, v| v.blank? })
  end

  private

  def terms_are_words
    words = terms.values.flat_map { |v| v.is_a?(Hash) ? v.values : Array(v) }
    errors.add(:terms, "must be 30 characters or fewer each") if words.any? { |w| w.to_s.length > 30 }
  end
end
