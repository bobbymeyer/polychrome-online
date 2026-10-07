# frozen_string_literal: true

# What happens: one closed set of outcomes, like the battle primitives, that
# everything outside battle gives. A field ability's success (FieldUse), an
# archetype's payoff at a rest (Job#payoff), and anything the party does
# somewhere (Pastime, which is also what a town's inn, temple and guild
# are). A world names and flavours them; the game knows what each does.
#
#   money 40    40 in the world's money, for the party
#   exp 20      20 EXP for each of them (standing)
#   abp 2       2 ABP for each of them, in their archetype
#   rumour      a rumour the party hasn't heard yet
#   rest 100    the night: sleep until the day begins. 100 is a bed (full
#               HP and MP, the KO'd back on their feet); less is camp (full
#               HP for those standing, that share of MP)
#   restore 25  25% of HP and MP back for everyone standing
#   raise       the KO'd back on their feet, whole
#   reveal      every place next to the party's comes into view
#   find 100    an item worth up to 100, into the chest
#   learn       the waiting encounter's weaknesses are known
#   sneak       the waiting encounter is avoided
#   safe road   the next dangerous path rolls no encounter
#   uncover     one of the GM's secrets comes out
#   story       the GM tells what happens
#
# And what a way can take (a fork's costly way in a dungeon: Toll), which a
# thing to do can ask too:
#   hurt 10     everyone standing loses 10% of their HP, never the last of it
#   weary 25    everyone standing loses 25% of their MP
#   ambush      a fight from the place's encounter table waits for the GM
#   lose 50     the party loses 50 of its money (what it has, at most)
#   time 2      two parts of the day go by
#   tick        a running clock goes on a segment: one at the party's place
#               if there is one, else the one nearest to full
#   give potion one of that item, out of the chest or a bag (a camp or road event's
#               choice: Campaign::Remarks)
#
# What takes is the GM's hard moves (Dungeon World's, ch. 20 of
# Procedural Storytelling in Game Design): a complication on a failed
# check can make one happen (Campaign::Remarks).
#
# Some act on something named (target), as a scene's ending or a full
# clock's does (Scene#outcome, Clock):
#   reveal      a place comes into view            { "node" => id }
#   mode        a place is set in a mode, or back  { "node" => id, "mode" => key or nil }
#   find        that item, into the chest          { "item" => slug } (a dungeon's treasure)
#   battle      a fight starts, now                { "name" => "...", "monsters" => { slug => count } }
Outcome = Data.define(:kind, :amount, :target)

class Outcome
  # kind => [what it does, its amount when none is given]
  KINDS = {
    "money" => [ "%{amount} for the party", 0 ],
    "exp" => [ "%{amount} EXP each", 0 ],
    "abp" => [ "%{amount} ABP each", 0 ],
    "rumour" => [ "A rumour the party hasn't heard", nil ],
    "rest" => [ "The night passes: %{rest}", 100 ],
    "restore" => [ "Everyone standing gets %{amount}% of %{hp} and %{mp} back", 25 ],
    "raise" => [ "The KO'd are back on their feet, whole", nil ],
    "reveal" => [ "Every place next to the party's comes into view", nil ],
    "find" => [ "An item worth up to %{amount}, into the chest", 100 ],
    "learn" => [ "The waiting encounter's weaknesses are known before the fight", nil ],
    "sneak" => [ "The encounter waiting on the road is avoided", nil ],
    "safe_road" => [ "The next dangerous path rolls no encounter", nil ],
    "uncover" => [ "One of the GM's secrets comes out (its next clue, if it comes a step at a time), one about where the party is if there is one", nil ],
    "story" => [ "The GM tells what happens", nil ],
    "mode" => [ "A place changes", nil ],
    "battle" => [ "A fight", nil ],
    "hurt" => [ "Everyone standing loses %{amount}% of %{hp}", 10 ],
    "weary" => [ "Everyone standing loses %{amount}% of %{mp}", 25 ],
    "ambush" => [ "Something there hears them: a fight", nil ],
    "lose" => [ "The party loses %{amount}", 50 ],
    "time" => [ "Time goes by: %{amount} of the day's parts", 1 ],
    "tick" => [ "A clock that matters goes on a segment", nil ],
    "give" => [ "The party gives up %{item}", nil ]
  }.freeze

  # What takes from the party, rather than giving: the hard moves.
  TAKES = %w[hurt weary ambush lose time tick].freeze

  # What a check can make happen on a success (Campaign#check!): anything
  # that needs nothing more to say than how much.
  ON_A_CHECK = %w[money exp abp rumour restore reveal find learn sneak safe_road uncover].freeze

  # What a camp or road event's choice can do: what a check can, what takes,
  # and giving something from the bag (Campaign::Remarks).
  ON_A_CHOICE = (ON_A_CHECK + TAKES + %w[give]).freeze

  # These need an encounter on the road to act on.
  NEEDS_ENCOUNTER = %w[sneak learn].freeze

  # "money 40", "+40 money", "rest", "safe road": an outcome, or nil.
  def self.parse(text)
    words = text.to_s.strip.downcase.sub(/\A\+/, "")
    # "give potion", "give phoenix down": an item, by its slug.
    return new(kind: "give", target: { "item" => words.delete_prefix("give").strip.tr(" -", "__") }) if words.match?(/\Agive\s+\S/)

    number = words[/\A\d+|\d+\z/]
    kind = words.sub(/\A\d+\s*|\s*\d+\z/, "").strip.tr(" ", "_").sub(/\A\+/, "")
    return unless KINDS.key?(kind)

    new(kind: kind, amount: number&.to_i)
  end

  def self.of(kind, amount = nil, target: nil) = new(kind: kind.to_s, amount: amount, target: target)

  def initialize(kind:, amount: nil, target: nil)
    super(kind: kind, amount: amount || KINDS.fetch(kind).last, target: target)
  end

  # How it's written in a thing to do's brackets: "money 40", "safe road".
  def to_s
    return "give #{target['item'].tr('_', ' ')}" if kind == "give"

    [ kind.tr("_", " "), (amount unless KINDS.fetch(kind).last.nil?) ].compact.join(" ")
  end

  # What it does, in the world's words.
  def describe(world)
    template = KINDS.fetch(kind).first
    shown = %w[money lose].include?(kind) ? "#{amount} #{world.word('currency')}" : amount
    rest = amount.to_i >= 100 ? "a bed, and everyone rested (the KO'd too)" : "camp, full #{world.word('hp')} for those standing and #{amount}% of #{world.word('mp')}"
    item = (world.items.find_by(slug: target["item"])&.name || target["item"].to_s.tr("_", " ") if kind == "give")
    { amount: shown, hp: world.word("hp"), mp: world.word("mp"), rest: rest, item: (item && Wording.a_or_an(item)) }
      .reduce(template) { |text, (key, value)| text.gsub("%{#{key}}", value.to_s) }
  end

  # Whether it can happen now; raises Refusal if not (before anything is paid).
  def can_happen!(campaign)
    raise Refusal, "There's no encounter on the road to #{kind == 'sneak' ? 'get past' : 'size up'}" if NEEDS_ENCOUNTER.include?(kind) && !campaign.pending_encounter
    raise Refusal, "The party isn't on the map" if kind == "reveal" && !target && !campaign.current_node
    raise Refusal, "Nobody is standing to fight" if kind == "battle" && campaign.characters.none?(&:conscious?)
    raise Refusal, "Nobody is KO'd" if kind == "raise" && campaign.characters.none? { |c| !c.conscious? }
    raise Refusal, "Not while a battle is on" if kind == "rest" && campaign.battle_on?
  end

  # Whether it would do anything now, for what takes: a hard move with
  # nothing to take is no move at all (no clock running, an empty purse,
  # nowhere for an ambush to come from).
  def bites?(campaign)
    standing = campaign.conscious_characters
    case kind
    when "hurt" then standing.any? { |c| c.current_hp > 1 }
    when "weary" then standing.any? { |c| c.current_mp.positive? }
    when "lose" then campaign.gil.positive?
    when "give" then (item = campaign.world.items.find_by(slug: target["item"])) && campaign.party_quantity_of(item).positive?
    when "tick" then !campaign.clock_to_tick.nil?
    when "ambush" then !(campaign.dungeon_in_progress || campaign.current_node&.location)&.location_template&.encounter_table.nil?
    else true
    end
  end

  # Makes it happen for the campaign. by: who did it ("Rook", "The party");
  # who: the characters it's for (EXP, ABP: those standing, by default).
  # line: the table's words, with {who}, {amount} and {rumour} filled in,
  # instead of the plain line, for what has an amount or a rumour to say.
  # source: what did it, for a secret it brings out ("Rook's Ask Around").
  # Returns the line the table hears, or nil if something else already said it.
  def apply!(campaign, by:, who: nil, line: nil, source: nil)
    who ||= campaign.conscious_characters
    send(:"#{kind}!", campaign, by: by, who: who, line: line, source: source)
  end

  private

  # Each makes it happen and returns its line, or nil.

  def money!(campaign, by:, line:, **)
    campaign.increment!(:gil, amount)
    text = campaign.money(amount)
    say(line, "#{by}: #{text}.", by: by, amount: text)
  end

  def exp!(_campaign, **) = gain(:exp, **)
  def abp!(_campaign, **) = gain(:abp, **)

  def gain(kind, by:, who:, line:, **)
    grew = who.filter_map do |character|
      gained = character.gain!(kind => amount)
      if gained["level"] then "#{character.name}: level #{gained['level'].last}!"
      elsif gained["job_level"] then "#{character.name}: #{character.job.name} level #{gained['job_level'].last}!"
      end
    end
    text = "#{amount} #{kind.upcase}"
    say(line, "#{by}: #{text}#{' each' if who.size > 1}.", by: by, amount: text) + grew.map { |g| " #{g}" }.join
  end

  def rumour!(campaign, by:, line:, **)
    rumour = campaign.rumour_for_sale
    return "#{by} listens, but hears nothing new." unless rumour

    rumour.update!(heard: true)
    campaign.hear_of!(rumour)
    say(line, "#{by} hears something: “#{rumour.body}”", by: by, rumour: "“#{rumour.body}”")
  end

  # The caller's own words for it, if it gave some, or the plain line.
  def say(line, plain, by:, amount: nil, rumour: nil)
    line.present? ? Generators::Lore.fill(line, who: by, amount: amount, rumour: rumour) : plain
  end

  def rest!(campaign, **)
    campaign.sleep!(bed: amount >= 100, mp_share: amount.clamp(0, 100))
    nil # the night says itself
  end

  def restore!(campaign, by:, who:, **)
    who.each do |c|
      c.update!(hp: [ c.current_hp + (c.stats["max_hp"] * amount / 100), c.stats["max_hp"] ].min,
                mp: [ c.current_mp + (c.stats["max_mp"] * amount / 100), c.stats["max_mp"] ].min)
    end
    "#{by} sees to everyone: #{amount}% of #{campaign.world.word('hp')} and #{campaign.world.word('mp')} back."
  end

  def raise!(campaign, **)
    fallen = campaign.characters.reload.reject(&:conscious?)
    fallen.each { |c| c.update!(hp: nil, mp: nil) }
    "#{fallen.map(&:name).to_sentence} #{fallen.one? ? 'is' : 'are'} raised, whole again."
  end

  def reveal!(campaign, by:, **)
    if target
      place = campaign.map_nodes.find(target["node"])
      return if place.visible?

      place.update!(visible: true)
      return "#{place.name} appears on the map."
    end
    node = campaign.current_node or return "#{by} looks around, but there's no map to read."
    hidden = campaign.map_edges.select { |e| e.touches?(node) }.map { |e| e.other_end(node) }.reject(&:visible?)
    return "#{by} looks around: nothing new in sight." if hidden.empty?

    hidden.each { |n| n.update!(visible: true) }
    "#{by} scouts ahead: #{hidden.map(&:name).to_sentence} come#{'s' if hidden.one?} into view."
  end

  def find!(campaign, by:, line:, **)
    return found!(campaign, by: by, line: line) if target
    finds = campaign.world.items.where(category: "consumable").where(price: 1..amount).order(:price, :id).to_a
    return "#{by} searches, but finds nothing worth the carrying." if finds.empty?

    item = campaign.roll { |dice| finds[dice.int(finds.size)] }
    campaign.add_item!(item)
    "#{by} finds #{Wording.a_or_an(item.name)}."
  end

  # A named thing found (a dungeon's treasure), whatever it's worth.
  def found!(campaign, by:, line:)
    item = campaign.world.items.find_by(slug: target["item"])
    campaign.add_item!(item) if item
    say(line, "#{by} finds #{item&.name || target['item']}.", by: by)
  end

  def learn!(campaign, by:, **)
    monsters = campaign.world.monsters.where(slug: campaign.pending_encounter.to_h.fetch("monsters", {}).keys)
    return "There's nothing on the road to read." if monsters.empty?

    known = campaign.known_affinities.deep_dup
    engine = campaign.world.type_chart.to_engine
    monsters.each do |monster|
      notes = (known[monster.slug] ||= {})
      notes["types"] = [ monster.base_type ]
      Battle::Types.list(engine).each { |type| notes[type] = monster.affinities.fetch(type, "none") }
      Battle::STATUSES.each { |status| notes[status] = monster.status_immune.include?(status) ? "immune" : "none" }
    end
    campaign.update!(known_affinities: known)
    "#{by} sizes up #{monsters.map(&:name).to_sentence}: their weaknesses are known."
  end

  def sneak!(campaign, by:, **)
    return "The road was already clear." unless campaign.pending_encounter

    campaign.update!(pending_encounter: nil)
    "#{by} gets the party past without a fight."
  end

  def safe_road!(campaign, by:, **)
    campaign.update!(safe_road: true)
    "#{by} finds a way through: the next dangerous path is safe."
  end

  def uncover!(campaign, by:, source:, **)
    secret = Secret.next_for(campaign) or return "#{by} digs, but there's nothing more to find out."
    secret.find_clue!(by: source || by)
    nil # the secret says itself
  end

  def story!(_campaign, by:, **) = "#{by} manages it. What happens is the GM's to tell."

  # A place set in a mode (MapNode#switch_mode!), or back to how it was.
  # The place says so itself.
  def mode!(campaign, **)
    place = campaign.map_nodes.find(target["node"])
    if target["mode"] then place.switch_mode!(target["mode"]) unless place.current_mode&.key == target["mode"]
    elsif place.current_mode then place.clear_mode!
    end
    nil
  end

  # Everyone standing loses a share of their HP (never the last of it) or MP.
  def hurt!(campaign, **) = toll(campaign, "hp", floor: 1)
  def weary!(campaign, **) = toll(campaign, "mp", floor: 0)

  def toll(campaign, stat, floor:)
    lost = campaign.conscious_characters.filter_map do |character|
      now = stat == "hp" ? character.current_hp : character.current_mp
      take = [ (character.stats["max_#{stat}"].to_i * amount / 100.0).ceil, now - floor ].min
      next unless take.positive?

      character.update!(stat => now - take)
      "#{character.name} −#{take}"
    end
    "It takes its toll: #{lost.join(', ')} #{campaign.world.word(stat)}." if lost.any?
  end

  # Something at the place the party is (the dungeon they're in, or the
  # place on the map) hears them: a fight from its encounter table waits
  # for the GM, as one on the road does.
  def ambush!(campaign, **)
    place = campaign.dungeon_in_progress || campaign.current_node&.location
    table = place&.location_template&.encounter_table or return "Nothing comes. This time."
    monsters = campaign.roll_with { |state| Pointcrawl::Encounters.roll(state, table.entries, "dangerous") } or return "Nothing comes. This time."

    campaign.waylay!("#{place.name}: on the way", monsters, terrain: table.terrain_type)
    "Encounter! #{campaign.describe_encounter(monsters)}."
  end

  def lose!(campaign, **)
    taken = [ amount, campaign.gil ].min
    return "The party has nothing to lose." unless taken.positive?

    campaign.decrement!(:gil, taken)
    "The party loses #{campaign.money(taken)}."
  end

  def give!(campaign, by:, **)
    item = campaign.world.items.find_by(slug: target["item"])
    return "#{by} has nothing like that to give." unless item && campaign.party_quantity_of(item).positive?

    campaign.take_from_party!(item)
    "#{by} gives up #{Wording.a_or_an(item.name)}."
  end

  def time!(campaign, **)
    campaign.pass_time!(amount)
    nil # the time says itself
  end

  # A public clock says so itself; a hidden one tells the GM alone.
  def tick!(campaign, **)
    clock = campaign.clock_to_tick or return "Nothing gets worse. This time."
    clock.tick!(1, reason: "things went wrong")
    campaign.narrate("#{clock.name}: #{clock.filled} of #{clock.segments}.", scope: "gm") unless clock.public? || clock.full?
    nil
  end

  # A fight, now: the stage takes everyone there.
  def battle!(campaign, **)
    # A boss among them makes it a boss fight: its entrance, and no fleeing it.
    boss = campaign.world.monsters.where(slug: target["monsters"].to_h.keys, boss: true).exists?
    campaign.waylay!(target["name"], target["monsters"], boss: boss)
    campaign.start_pending_encounter!
    nil
  end
end
