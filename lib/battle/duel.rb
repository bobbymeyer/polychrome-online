# frozen_string_literal: true

module Battle
  # A duel (Oda): two people, to KO, and a different battle from a fight.
  # Not whoever has the bigger numbers: whoever reads the other.
  #
  # Each exchange both duellists pick a stance in secret; they are shown
  # together. Strike beats Feint, Guard beats Strike, Feint beats Guard. The
  # winner lands a heavy blow; two Strikes trade light ones; matching Guards
  # or Feints circle. Stats and archetype set how hard a blow lands, never
  # who wins the exchange.
  #
  # The opponent is one the GM plays (an enemy unit): its stance for the
  # next exchange is drawn when the last one ends, and it gives a tell, a
  # line that usually gives the stance away (TELL_TRUTH) and sometimes
  # bluffs. The GM can say it in their own words. The drawn stance waits in
  # the state ("duel" → "planned") and the views never show it.
  #
  # Each archetype has a technique (a unit's "technique"), once a duel
  # unless it says otherwise:
  #   wait     (Courtsword) chosen: hold this exchange, and the next one won
  #            lands DRAW_POWER: the last-second draw
  #   opening  (Mancer)     a shot before the first stare
  #   read     (Thief)      chosen, before picking: the tell is read plainly
  #   tie_win  (Monk)       the first tie counts as a win
  #   switch   (Magician)   the first exchange it would lose, it ties instead
  #   recover  (Healer)     a little HP back after every exchange
  #   steady   (Ranger)     the first Strike that loses still lands lightly
  # No items, no allies, no fleeing: fleeing is refusing.
  module Duel
    STANCES = %w[strike guard feint].freeze
    BEATS = { "strike" => "feint", "guard" => "strike", "feint" => "guard" }.freeze
    TECHNIQUES = %w[wait opening read tie_win switch recover steady].freeze
    # Chosen by the player, with their command; the rest happen by themselves.
    CHOSEN = %w[wait read].freeze
    # Every exchange, not once a duel.
    EVERY_TIME = %w[recover].freeze

    HEAVY_POWER = 150
    LIGHT_POWER = 60
    DRAW_POWER = 300
    OPENING_POWER = 40
    RECOVER_PERCENT = 8
    TELL_TRUTH = 75

    # What a duellist says without lines of their own.
    TELLS = {
      "strike" => [ "Enough talk.", "I'll end this now!", "Their weight shifts forward." ],
      "guard" => [ "Come, then.", "They settle in, patient.", "Show me what you have." ],
      "feint" => [ "Are you watching closely?", "A smile, and a loose grip.", "Their eyes go somewhere else." ]
    }.freeze

    module_function

    def validate!(units)
      party = units.select { |u| u["side"] == "party" }
      enemy = units.select { |u| u["side"] == "enemy" }
      raise ArgumentError, "a duel is one against one" unless party.size == 1 && enemy.size == 1
    end

    # The duel's own state, before the first exchange is planned (#open).
    def opening
      { "exchange" => 1, "used" => {}, "drawn" => [] }
    end

    def duel?(state)
      state["kind"] == "duel"
    end

    # The first stance and its tell, drawn as the duel is built.
    def open(state)
      ctx = Context.new(state)
      plan(ctx, announce: false)
      ctx.finish.first
    end

    def party_unit(ctx) = ctx.units.find { |u| u["side"] == "party" && !u["guest"] }
    def opponent(ctx) = ctx.units.find { |u| u["side"] == "enemy" }

    # The opponent's next stance, and the tell that goes with it.
    def plan(ctx, announce: true)
      foe = opponent(ctx)
      stance = STANCES[ctx.rng.int(STANCES.size)]
      truthful = ctx.rng.percent?(TELL_TRUTH)
      shown = truthful ? stance : (STANCES - [ stance ])[ctx.rng.int(2)]
      own = foe.dig("tells", shown)
      lines = own && !own.empty? ? own : TELLS.fetch(shown)
      line = lines[ctx.rng.int(lines.size)]
      ctx.state["duel"]["planned"] = stance
      ctx.state["duel"]["tell"] = { "unit" => foe["id"], "line" => line }
      ctx.emit(:tell, unit: foe["id"], line: line) if announce
    end

    def used?(ctx, unit, technique)
      Array(ctx.state["duel"]["used"][unit["id"]]).include?(technique)
    end

    def has?(ctx, unit, technique)
      unit["technique"] == technique && (EVERY_TIME.include?(technique) || !used?(ctx, unit, technique))
    end

    def use!(ctx, unit, technique, **extra)
      (ctx.state["duel"]["used"][unit["id"]] ||= []) << technique unless EVERY_TIME.include?(technique)
      ctx.emit(:technique, actor: unit["id"], technique: technique, **extra)
    end

    # Read (a Thief's technique): the opponent's planned stance, plainly. No
    # RNG: it was drawn already. It isn't their command for the exchange.
    def read(ctx, unit)
      raise InvalidAction, "#{unit['name']} can't read anyone" unless has?(ctx, unit, "read")

      use!(ctx, unit, "read", target: opponent(ctx)["id"], stance: ctx.state["duel"]["planned"])
      ctx.state["duel"]["read"] = ctx.state["duel"]["planned"]
    end

    # One exchange, from the party's stance (its command) and the planned
    # one. Returns when it's resolved; the caller closes the round.
    def exchange(ctx, command)
      hero = party_unit(ctx)
      foe = opponent(ctx)
      duel = ctx.state["duel"]
      ctx.emit(:stare, exchange: duel["exchange"])
      opening_shots(ctx, [ hero, foe ]) if duel["exchange"] == 1
      return if ctx.over?

      waiting = command && command["technique"] == "wait" && has?(ctx, hero, "wait")
      stances = { hero["id"] => waiting ? "wait" : command&.dig("stance") || "strike", foe["id"] => duel["planned"] }
      use!(ctx, hero, "wait") if waiting
      ctx.emit(:reveal, stances: stances)
      outcome(ctx, hero, foe, stances)
      ctx.check_end
      return if ctx.over?

      [ hero, foe ].each { |unit| recover(ctx, unit) }
      duel["exchange"] += 1
      duel.delete("read")
      plan(ctx)
    end

    def opening_shots(ctx, units)
      units.each do |unit|
        next unless ctx.alive?(unit) && has?(ctx, unit, "opening")

        target = units.find { |u| u != unit }
        use!(ctx, unit, "opening", target: target["id"])
        blow(ctx, unit, target, OPENING_POWER, magic: true)
        ctx.check_end
        break if ctx.over?
      end
    end

    def outcome(ctx, hero, foe, stances)
      a = stances[hero["id"]]
      b = stances[foe["id"]]
      if a == "wait" || b == "wait"
        waiter, other = a == "wait" ? [ hero, foe ] : [ foe, hero ]
        ctx.state["duel"]["drawn"] |= [ waiter["id"] ]
        ctx.emit(:clash, result: "wait", unit: waiter["id"])
        blow(ctx, other, waiter, LIGHT_POWER) if stances[other["id"]] == "strike"
        return
      end

      winner, loser = decide(ctx, hero, foe, a, b)
      if winner
        ctx.emit(:clash, result: "win", winner: winner["id"], loser: loser["id"])
        steady(ctx, loser, winner, stances[loser["id"]])
        drawn = ctx.state["duel"]["drawn"].delete(winner["id"])
        blow(ctx, winner, loser, drawn ? DRAW_POWER : HEAVY_POWER) if ctx.alive?(winner) && ctx.alive?(loser)
      elsif a == "strike"
        ctx.emit(:clash, result: "trade")
        blow(ctx, hero, foe, LIGHT_POWER)
        blow(ctx, foe, hero, LIGHT_POWER) unless ctx.over?
      else
        ctx.emit(:clash, result: "circle")
      end
      # A draw is for the exchange after the wait: won or not, it passes.
      ctx.state["duel"]["drawn"] = []
    end

    # Who wins, after the techniques that bend it: a Magician's switch turns
    # a loss into a tie, a Monk's tie_win turns a tie into a win.
    def decide(ctx, hero, foe, a, b)
      winner = if BEATS[a] == b then hero
      elsif BEATS[b] == a then foe
      end
      if winner
        loser = winner == hero ? foe : hero
        if has?(ctx, loser, "switch")
          use!(ctx, loser, "switch", stance: winner == hero ? a : b)
          return tie(ctx, hero, foe)
        end
        return [ winner, loser ]
      end
      tie(ctx, hero, foe)
    end

    def tie(ctx, hero, foe)
      monk = [ hero, foe ].find { |u| has?(ctx, u, "tie_win") }
      return [ nil, nil ] unless monk

      use!(ctx, monk, "tie_win")
      [ monk, monk == hero ? foe : hero ]
    end

    # A Ranger's Strike that lost still finds its mark, lightly, once.
    def steady(ctx, loser, winner, stance)
      return unless stance == "strike" && has?(ctx, loser, "steady")

      use!(ctx, loser, "steady", target: winner["id"])
      blow(ctx, loser, winner, LIGHT_POWER)
    end

    def recover(ctx, unit)
      return unless ctx.alive?(unit) && has?(ctx, unit, "recover") && unit["hp"] < unit["stats"]["max_hp"]

      use!(ctx, unit, "recover")
      ctx.restore_hp(unit, [ unit["stats"]["max_hp"] * RECOVER_PERCENT / 100, 1 ].max, actor: unit["id"])
    end

    # A blow in a duel always lands: the exchange decided that. It's the
    # better of the duellist's arm and their magic, softened by the matching
    # defence, through the type chart. magic: always their magic (a shot).
    def blow(ctx, actor, target, power, magic: false)
      return unless ctx.alive?(actor) && ctx.alive?(target)

      arm = (ctx.stat(actor, "atk") + ctx.stat(actor, "str")) * power / 100
      spell = Effects.scale_by_mag(ctx, actor, power / 5)
      amount = if magic || spell > arm
                 Effects.mitigate(Effects.vary(ctx, spell), ctx.stat(target, "mdef"))
      else
                 Effects.mitigate(Effects.vary(ctx, arm), ctx.stat(target, "def"))
      end
      type = actor["attack_type"]
      Effects.typed(ctx, actor, target, type, [ amount, 1 ].max)
    end
  end
end
