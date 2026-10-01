# frozen_string_literal: true

# Facts about the moment, for the story matcher (Story::Matcher; docs/STORY.md,
# item 6): where the party is, when, how it's doing, the clocks and the
# GM's flags, as one flat hash a row's "when" asks about. FACTS says what
# each is, for whoever writes rows (the Generator Tables' facts page).
#
# Words become keys as flags do ("Market day" is market_day). The game's own
# facts win over a flag of the same name.
module Campaign::Moment
  extend ActiveSupport::Concern

  # What a row can ask about: key (as written) => what it is.
  FACTS = {
    "place" => "The place's name: place = Hollin.",
    "town, dungeon, landmark, wilds, field" => "True for the kind of place the party is at.",
    "mode" => "The name of the first mode the place is in (the city burns); each mode it's in is true by its key too.",
    "first_visit" => "True the first time the party arrives here.",
    "visits" => "How many times the party has arrived here before this.",
    "cleared" => "True at a dungeon whose boss has fallen.",
    "standing, reputation" => "In a town: how it sees the party (strangers, wary, welcome…) and the number behind it, -5 to 5.",
    "time" => "The part of the day, as the setting names it; that name is true too (night, dusk).",
    "dawn, day, dusk, night, dark" => "The light, whatever the setting calls its parts of the day; dark is true in any of its night.",
    "weekday, month, season" => "The date, as the setting's calendar has it; each name is true too (winter, market_day).",
    "day" => "Days since the story began, counting from 1.",
    "party" => "How many of the party are standing.",
    "hurt" => "How many of those are under half their HP.",
    "down" => "How many of the party are knocked out.",
    "home" => "Who of the party is from here, by name (Vivi, or Vivi and Bartz); true when anyone is.",
    "hurt_one" => "The one of the party standing who is worst hurt, under half their HP, by name.",
    "tied, tied_to" => "One of the party with a tie, by name, and who they're tied to.",
    "from_<origin>" => "Who of the party is of that origin, by name (from_highlands = Vivi).",
    "gil" => "What the party has to spend.",
    "clock_<name>" => "How many segments of a running or full clock are filled (clock_the_wolves_gather >= 4).",
    "<secret key>, <secret key>_known" => "For a secret with a key: how many of its clues the party has found, and true once they know the " \
                                          "secret itself (mayors_lamp >= 1, !mayors_lamp_known: they're asking, but don't know yet).",
    "<flag>" => "Every flag the GM has set, and every one a row has remembered, by its key."
  }.freeze

  # Facts about the party at a map place (where it is, unless told).
  def moment(at: current_node)
    facts = flags.to_h { |flag| [ flag.key, flag.counter? ? flag.value.to_i : flag.value ] }
    facts.merge!(place_facts(at)) if at
    facts.merge!(time_facts, party_facts(at), clock_facts, secret_facts)
  end

  # How many times the party had arrived at a place before.
  def visits_to(node) = visits.to_h.fetch(node.id.to_s, 0).to_i

  # One more arrival at a place.
  def count_visit!(node)
    update!(visits: visits.to_h.merge(node.id.to_s => visits_to(node) + 1))
  end

  def self.key(word)
    key = word.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    key.match?(/\A[a-z]/) ? key : (key.empty? ? nil : "n_#{key}")
  end

  private

  def place_facts(node)
    facts = { "place" => node.name, node.kind => true, "visits" => visits_to(node), "first_visit" => visits_to(node).zero? }
    modes = node.modes_on
    facts["mode"] = modes.first.name if modes.any?
    modes.each { |mode| facts[Campaign::Moment.key(mode.key)] = true }
    location = node.location
    facts["cleared"] = location.cleared? if location&.dungeon?
    if location&.town?
      facts["reputation"] = location.reputation
      facts["standing"] = location.standing.downcase
    end
    facts.compact
  end

  def time_facts
    at = almanac.moment(day)
    facts = { "time" => period.downcase, "day" => day, daylight => true, "dark" => dark? }
    facts[Campaign::Moment.key(period)] = true
    { "weekday" => at.weekday, "month" => at.month, "season" => at.season }.each do |what, name|
      next if name.blank?

      facts[what] = name.downcase
      facts[Campaign::Moment.key(name)] = true
    end
    facts
  end

  def party_facts(node)
    everyone = characters.includes(:job, :character_jobs, equipment_slots: :item).to_a
    standing = everyone.select(&:conscious?)
    home = node ? everyone.select { |c| c.home_node_id == node.id }.map(&:name) : []
    hurt = standing.select { |c| c.current_hp * 2 < c.stats["max_hp"] }
    tie_npcs = everyone.any? { |c| c.ties.any? } ? npcs.pluck(:id, :name).to_h : {}
    tied = everyone.find { |c| c.ties.any? { |tie| tie_npcs[tie["npc_id"]] } }
    facts = { "party" => standing.size, "hurt" => hurt.size, "down" => everyone.size - standing.size, "gil" => gil,
              "home" => home.to_sentence.presence, "hurt_one" => hurt.min_by { |c| c.current_hp.fdiv(c.stats["max_hp"]) }&.name,
              "tied" => tied&.name, "tied_to" => tied && tie_npcs[tied.ties.find { |tie| tie_npcs[tie["npc_id"]] }["npc_id"]] }
    everyone.select(&:origin).group_by(&:origin).each do |origin, people|
      key = Campaign::Moment.key(origin) or next
      facts["from_#{key}"] = people.map(&:name).to_sentence
    end
    facts.compact
  end

  def secret_facts
    secrets.where.not(key: nil).each_with_object({}) do |secret, facts|
      facts[secret.key] = secret.found
      facts["#{secret.key}_known"] = secret.revealed?
    end
  end

  def clock_facts
    clocks.where(stopped_at: nil).to_h { |clock| [ "clock_#{Campaign::Moment.key(clock.name)}", clock.filled ] }
  end
end
