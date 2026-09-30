# frozen_string_literal: true

# A place's past (Generators::History, Generators::Provenance) in words:
# who founded it, who its old rivals are, the feud still running, what a
# dungeon was and how it fell. Plain lines, for the location page, the
# atlas and the codex.
#
#   { "founded" => 94, "founder" => "Aldo Vell", "family" => "Vell", "holder" => "Pike",
#     "rival" => "Marrow", "feud" => { "with" => "Marrow", "cause" => "a horse sold lame" },
#     "was" => "manor", "fall" => { "kind" => "fire", "ago" => 38 }, "lost" => ["Pell Vell"],
#     "heirlooms" => [{ "name" => "the Vell signet", "maker", "made_for" }], "edited" => true }
class Past
  FIELDS = %w[founded founder family holder rival was lost].freeze

  attr_reader :data

  # lore: the world's (Generators::Lore), for how its falls are told.
  def initialize(data, lore: nil)
    @data = data.is_a?(Hash) ? data.stringify_keys : {}
    @lore = lore
  end

  def present? = (data.keys - %w[key name kind edited]).any?
  def edited? = data["edited"] == true

  def lines
    return [] unless present?

    data["was"] ? dungeon_lines : town_lines
  end

  def to_s = lines.join(" ")

  private

  def ago(years) = Generators::History.ago(years.to_i)
  def plural(name) = Generators::History.plural(name)
  def house(name, cap: false) = Generators::History.house(name, cap: cap)

  def town_lines
    [ ("Founded #{ago(data['founded'])}#{" by #{data['founder']}" if data['founder']}." if data["founded"]),
      ("#{house(data['family'], cap: true)} left #{ago(data['founders_left'])}." if data["family"] && data["founders_left"]),
      ("#{house(data['family'], cap: true)}' old rivals are #{house(data['rival'])}." if data["family"] && data["rival"] && data["rival"] != data.dig("feud", "with")),
      feud_line ].compact
  end

  def dungeon_lines
    fall = @lore&.dig("falls", data.dig("fall", "kind"))
    fell = data.dig("fall", "ago")
    [ "Once #{data['family'] ? "the #{data['family']}" : data['was'].to_s.match?(/\A[aeiou]/) ? 'an' : 'a'} #{data['was']}#{", built #{ago(data['founded'])}" if data['founded']}.",
      (if fall then "It #{fall['did'] || 'fell'} #{ago(fell)}#{", and was #{fall['sealed']}" if fall['sealed']}."
       elsif data.dig("fall", "kind") == "abandoned" then "Left empty #{ago(fell)}, when #{data['holder'] ? "#{house(data['holder'])}" : 'its people'} went away."
       elsif data.dig("fall", "kind") then "It fell #{ago(fell)}: #{data.dig('fall', 'kind')}."
       end),
      ("#{Array(data['lost']).to_sentence} never came out." if Array(data["lost"]).any?),
      ("#{house(data['holder'], cap: true)} bought it from #{house(data['family'])}." if data["holder"] && data["family"] && data["holder"] != data["family"]),
      *Array(data["heirlooms"]).map { |h| heirloom_line(h) },
      feud_line ].compact
  end

  def feud_line
    feud = data["feud"]
    return unless feud.is_a?(Hash) && feud["with"].present?

    "#{house(data['family'] || 'founder', cap: true)} are still at feud with #{house(feud['with'])}#{", over #{feud['cause']}" if feud['cause'].present?}."
  end

  def heirloom_line(heirloom)
    made = [ ("made by #{heirloom['maker']}" if heirloom["maker"]), ("for #{heirloom['made_for']}" if heirloom["made_for"]) ].compact.join(" ")
    "#{heirloom['name'].to_s.upcase_first} was lost there#{" (#{made})" if made.present?}."
  end
end
