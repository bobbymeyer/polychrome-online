# frozen_string_literal: true

# A town's services, paid from the party's purse: the inn, the temple and
# the guild; and resting, at an inn or out in the world.
module Campaign::Services
  extend ActiveSupport::Concern

  # What a town's services charge, from the party's purse: gil per level of
  # the character served, with a floor. A rumour costs the same for anyone.
  SERVICE_PRICES = { "inn" => [ 5, 10 ], "temple" => [ 20, 50 ], "guild" => [ 0, 30 ] }.freeze
  SERVICE_OFFERS = { "inn" => "a room for the night", "temple" => "a raising", "guild" => "a rumour" }.freeze

  def service_price(kind, character)
    per_level, floor = SERVICE_PRICES.fetch(kind)
    [ per_level * character.level, floor ].max
  end

  # A character pays for a service in the town the party is in:
  #   inn    — a night's rest: full HP and MP (the fallen need a temple)
  #   temple — a fallen character raised, at full HP and MP
  #   guild  — a rumour: the GM owes them one
  def use_service!(kind, character, at:, by:)
    raise Refusal, "Not while a battle is on" if battle_on?
    raise Refusal, "#{character.name} isn't in this party" unless character.campaign_id == id
    service = at.view.fetch("services", []).find { |s| s["kind"] == kind } or raise Refusal, "#{at.name} has no #{kind}"
    raise Refusal, "The #{service['name']} is shut: #{at.current_mode['name'].downcase}" if at.respond_to?(:service_closed?) && at.service_closed?(kind)
    case kind
    when "inn"
      raise Refusal, "#{character.name} is down: an inn can't help the fallen. A temple can." unless character.conscious?
      raise Refusal, "#{character.name} is already rested" if rested?(character)
    when "temple"
      raise Refusal, "#{character.name} is still on their feet" if character.conscious?
    end

    cost = service_price(kind, character)
    transaction do
      reload
      raise Refusal, "The party has #{money(gil)}; #{SERVICE_OFFERS.fetch(kind)} for #{character.name} costs #{cost}" if cost > gil

      update!(gil: gil - cost)
      character.update!(hp: nil, mp: nil) if %w[inn temple].include?(kind)
      character.update!(field_used: false) if kind == "inn" # a night's rest: field abilities are back
      narrate(service_line(kind, character, service, by, cost))
    end
  end

  # Everyone who needs it takes a room, in one payment.
  def rest_at_inn!(at:, by:)
    tired = characters.order(:created_at).select { |c| c.conscious? && !rested?(c) }
    raise Refusal, "Everyone standing is already rested" if tired.empty?

    cost = tired.sum { |c| service_price("inn", c) }
    raise Refusal, "The party has #{money(gil)}; rooms for everyone cost #{cost}" if cost > gil

    transaction do
      tired.each { |c| use_service!("inn", c, at: at, by: by) }
      tick_clocks!("rest")
      pass_time!(until_dawn, announce: :new_day)
    end
  end

  def rested?(character)
    character.current_hp == character.stats["max_hp"] && character.current_mp == character.stats["max_mp"]
  end

  def rest!
    raise Refusal, "Not while a battle is on" if battle_on?

    transaction do
      characters.update_all(hp: nil, mp: nil, field_used: false)
      narrate("The party rests. Everyone is back to full #{world.word('hp')} and #{world.word('mp')}.")
      tick_clocks!("rest")
      pass_time!(until_dawn, announce: :new_day)
    end
  end

  private

  # What the table hears when a service is paid for.
  def service_line(kind, character, service, by, cost)
    payer = by == character.name ? character.name : "#{by}, for #{character.name},"
    case kind
    when "inn" then "#{payer} takes a room at #{service['name']} (#{money(cost)}). #{character.name} is rested: full #{world.word('hp')} and #{world.word('mp')}."
    when "temple" then "#{payer} pays #{money(cost)} at #{service['name']}. #{character.name} is raised, whole again."
    when "guild" then "#{payer} buys a rumour at #{service['name']} (#{money(cost)}). The GM owes #{character.name} something true."
    end
  end
end
