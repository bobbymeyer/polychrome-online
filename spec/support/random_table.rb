# frozen_string_literal: true

# A chaotic but legal table: random players, an impatient timer and a
# meddling GM. Drives property specs. Uses its own Random, separate from
# the battle's RNG, so the resolver's determinism is what's under test.
class RandomTable
  attr_reader :initial, :actions, :steps

  # Played once per process and shared between examples: it's pure data.
  def self.played(seeds)
    @played ||= {}
    @played[seeds] ||= seeds.map { |seed| new(seed).tap(&:play) }
  end

  def initialize(seed, enemies: nil)
    @chooser = Random.new(seed)
    @initial = Battle::State.build(
      seed: seed,
      party: BattleFixtures.party.sample(@chooser.rand(1..4), random: @chooser)
                           .map { |u|
                             u.merge(desperation: %w[goblin_punch meteor firaga_all].sample(random: @chooser),
                                     passives: Battle::PASSIVES.sample(@chooser.rand(0..2), random: @chooser),
                                     abilities: u[:abilities] + %w[cover jump gaia hide banish high_jump barrier taunt stop rage confuse focus flame_blade gravity osmose
                                                                            blood_strike holy comet sneak_attack doom reckless revenge call_eagle call_wisp]
                                                                         .sample(5, random: @chooser))
                              .merge(job_parts(u))
                           },
      terrain: Battle::TYPES.sample(random: @chooser),
      enemies: enemies || [ BattleFixtures.goblins(@chooser.rand(1..4)), BattleFixtures.ogre, BattleFixtures.skeletons(@chooser.rand(1..3)) ].sample(random: @chooser),
      abilities: BattleFixtures.abilities,
      summons: BattleFixtures.summons,
      escapable: @chooser.rand(4) != 0,
      items: BattleFixtures.items(potion: @chooser.rand(0..3), phoenix_down: @chooser.rand(0..2),
                                  antidote: @chooser.rand(0..2), remedy: @chooser.rand(0..1)),
      # Half the tables play One More (from the seed, so the rest of the table is drawn as before).
      rules: { one_more: seed.odd? }
    )
    @actions = []
    @steps = [] # [state_before, action, state_after, events]
  end

  def play(max_actions: 400)
    state = initial
    max_actions.times do
      break unless state["status"] == "input"

      action = next_action(state)
      after, events = Battle::Resolver.apply(state, action)
      @actions << action
      @steps << [ state, action, after, events ]
      state = after
    end
    state
  end

  private

  # What a character's jobs bring: a type for Attack, a signature, and
  # mastery on some of what they know.
  def job_parts(unit)
    return {} if @chooser.rand(3).zero?

    known = unit[:abilities] + %w[attack]
    mastery = known.sample(@chooser.rand(0..3), random: @chooser).to_h do |id|
      entry = { "power" => [ 100, 125, 150, 175 ].sample(random: @chooser) }
      entry["stats"] = { "mag" => @chooser.rand(5..40), "str" => @chooser.rand(5..40) } if @chooser.rand(2).zero?
      [ id, entry ]
    end
    { attack_type: Battle::TYPES.sample(random: @chooser), signature: unit[:abilities].sample(random: @chooser),
      immune_as_resist: true, mastery: mastery }
  end

  def next_action(state)
    # A GM at the table rules on an idea soon after it's made.
    if state["inputs"].any? { |_, c| c["kind"] == "custom" && !c["ruling"] } && @chooser.rand(2).zero?
      return rule(state)
    end

    roll = @chooser.rand(100)
    return { "type" => "timeout" } if roll < 8
    return gm_action(state) if roll < 14

    awaiting = Battle::State.awaiting_input(state)
    return { "type" => "timeout" } if awaiting.empty?

    chosen = awaiting.sample(random: @chooser)
    player_command(state, state["units"].find { |u| u["id"] == chosen })
  end

  def player_command(state, u)
    roll = @chooser.rand(100)
    return cmd(u, "kind" => "custom", "text" => "tries something daring", "target" => state["units"].sample(random: @chooser)["id"]) if roll < 4
    return cmd(u, "kind" => "defend") if roll < 8
    return cmd(u, "kind" => "flee") if roll < 11 && state["escapable"]
    if roll < 22
      item = state["items"].values.select { |i| Battle::State.items_left(state, i["id"], except: u["id"]).positive? }.sample(random: @chooser)
      return cmd(u, "kind" => "item", "item" => item["id"], "target" => target_for(state, u, item)) if item
    end

    usable = u["abilities"].map { |id| state["abilities"][id] }.select { |a| Battle::State.usable?(u, a) }
    ability = usable.sample(random: @chooser)
    command = { "kind" => "ability", "ability" => ability["id"], "target" => target_for(state, u, ability) }
    command["timing"] = "perfect" if @chooser.rand(4).zero?
    cmd(u, command)
  end

  # A target the engine offers (State.target_options: the menu's own list), a cure aimed at whoever
  # needs it first; sometimes none at all, leaving it to the engine.
  def target_for(state, u, ability)
    if ability["effects"].any? { |e| e["primitive"] == "cleanse" } # a player cures whoever needs it
      sick = state["units"].select { |o| o["side"] == u["side"] && o["hp"].positive? && !o["gone"] && o["statuses"].any? }
      return sick.sample(random: @chooser)["id"] if sick.any?
    end
    pool = Battle::State.target_options(state, u, ability) || []
    pool = pool.select { |id| state["units"].find { |o| o["id"] == id }["side"] == u["side"] } if ability["target"] == "single_ally" # support stays on the party
    return nil if pool.empty? || @chooser.rand(5).zero? # sometimes leave it to the engine

    pool.sample(random: @chooser)
  end

  def cmd(u, command)
    { "type" => "command", "actor" => u["id"], "command" => command }
  end

  def gm_action(state)
    target = state["units"].reject { |u| u["gone"] }.sample(random: @chooser)
    alive = state["units"].select { |u| u["hp"].positive? && !u["gone"] }
    case @chooser.rand(9)
    when 0 then { "type" => "gm_override", "op" => "execute_round" }
    when 1 then { "type" => "gm_override", "op" => "set_hp", "unit" => target["id"],
                  "value" => @chooser.rand(-10..(target["stats"]["max_hp"] + 10)) }
    when 2 then { "type" => "gm_override", "op" => "set_mp", "unit" => target["id"], "value" => @chooser.rand(0..50) }
    when 3
      u = alive.sample(random: @chooser)
      { "type" => "gm_override", "op" => "add_status", "unit" => u["id"],
        "status" => (Battle::STATUSES - Battle::PRIMITIVE_STATUSES).sample(random: @chooser), "turns" => @chooser.rand(1..4) }
    when 4 then { "type" => "gm_override", "op" => "remove_status", "unit" => target["id"],
                  "status" => (Battle::STATUSES - Battle::PRIMITIVE_STATUSES).sample(random: @chooser) }
    when 5
      side = @chooser.rand(3).zero? ? "party" : "enemy"
      spec = side == "party" ? BattleFixtures.party.sample(random: @chooser).merge(ai: [ { use: "attack" } ]) : BattleFixtures.goblins(1).first.except(:count)
      { "type" => "gm_override", "op" => "add_unit", "side" => side, "unit" => Battle::State.normalize(spec) }
    when 7 then rule(state)
    when 6
      leaving = state["units"].select { |u| (u["side"] == "enemy" || u["guest"]) && !u["gone"] }.sample(random: @chooser)
      return { "type" => "gm_override", "op" => "execute_round" } unless leaving

      { "type" => "gm_override", "op" => "dismiss", "unit" => leaving["id"] }
    else
      missing = Battle::State.awaiting_input(state)
      return { "type" => "timeout" } if missing.empty?

      { "type" => "gm_override", "op" => "auto", "unit" => missing.sample(random: @chooser) }
    end
  end

  def rule(state)
    pending = state["inputs"].find { |_, c| c["kind"] == "custom" && !c["ruling"] }
    return { "type" => "gm_override", "op" => "execute_round" } unless pending

    effects = [ [ { "primitive" => "physical", "power" => 150 } ], [ { "primitive" => "status", "kind" => "sleep", "chance" => 60 } ], [] ].sample(random: @chooser)
    { "type" => "gm_override", "op" => "rule", "unit" => pending.first, "stat" => Stats::Check::STATS.sample(random: @chooser),
      "difficulty" => Stats::Check::DIFFICULTIES.keys.sample(random: @chooser), "aim" => %w[single_enemy all_enemies].sample(random: @chooser),
      "effects" => effects, "success" => "It works!", "failure" => "It doesn't." }
      .merge(@chooser.rand(2).zero? ? { "skill" => "Athletics", "bonus" => [ 0, 15 ].sample(random: @chooser) } : {})
  end
end
