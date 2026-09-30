# frozen_string_literal: true

# A town's services, paid from the party's purse: the inn, the temple and
# the guild. In a town the party rests at the inn, which heals everyone,
# the fallen too; on the road it makes camp, which raises nobody.
module Campaign::Services
  extend ActiveSupport::Concern

  # What a town's services charge, from the party's purse: gil per level of
  # the character served, with a floor. A rumour costs the same for anyone.
  SERVICE_PRICES = { "inn" => [ 5, 10 ], "temple" => [ 20, 50 ], "guild" => [ 0, 30 ] }.freeze
  SERVICE_OFFERS = { "inn" => "a room for the night", "temple" => "a raising", "guild" => "a rumour" }.freeze

  def service_price(kind, character)
    return 0 if kind == "inn" && free_rooms? # a town's thanks (Campaign::Deeds#welcome_back!)

    per_level, floor = SERVICE_PRICES.fetch(kind)
    [ per_level * character.level, floor ].max
  end

  # A character pays for a service in the town the party is in:
  #   inn    — a night's rest: full HP and MP, the fallen back on their
  #            feet, until the next dawn
  #   temple — a fallen character raised now, at full HP and MP (no night to wait)
  #   guild  — a rumour: one the party hasn't heard yet, or the GM owes them one
  # night: false when rest_at_inn! takes the whole party's night itself.
  # stay: take the room even if they're rested (a night in town).
  def use_service!(kind, character, at:, by:, night: true, stay: false)
    raise Refusal, "Not while a battle is on" if battle_on?
    raise Refusal, "#{character.name} isn't in this party" unless character.campaign_id == id
    service = at.view.fetch("services", []).find { |s| s["kind"] == kind } or raise Refusal, "#{at.name} has no #{kind}"
    raise Refusal, "The #{service['name']} is shut: #{at.shut_by(kind).name.downcase}" if at.respond_to?(:shut_by) && at.shut_by(kind)
    refuse_if_shunned!(at)
    case kind
    when "inn"
      raise Refusal, "#{character.name} is already rested" if rested?(character) && !stay
    when "temple"
      raise Refusal, "#{character.name} is still on their feet" if character.conscious?
    end

    cost = service_price(kind, character)
    transaction do
      reload
      raise Refusal, "The party has #{money(gil)}; #{SERVICE_OFFERS.fetch(kind)} for #{character.name} costs #{cost}" if cost > gil

      update!(gil: gil - cost)
      down = !character.conscious?
      character.update!(hp: nil, mp: nil) if %w[inn temple].include?(kind)
      character.update!(field_used: false) if kind == "inn" # a night's rest: field abilities are back
      bought = rumour_for_sale if kind == "guild"
      line = service_line(kind, character, service, by, cost, bought, down: down)
      narrate(line)
      hear_of!(bought) if bought
      if kind == "inn" && night
        tick_clocks!("rest")
        pass_time!(rest_time, announce: :new_day)
      end
      line
    end
  end

  # Everyone who needs it takes a room, in one payment; if nobody does, the
  # whole party stays the night anyway (waiting on something in town).
  def rest_at_inn!(at:, by:)
    party = characters.order(:created_at).to_a
    tired = party.reject { |c| rested?(c) }
    tired = party if tired.empty?

    cost = tired.sum { |c| service_price("inn", c) }
    raise Refusal, "The party has #{money(gil)}; rooms for everyone cost #{cost}" if cost > gil

    transaction do
      tired.each { |c| use_service!("inn", c, at: at, by: by, night: false, stay: true) }
      tick_clocks!("rest")
      pass_time!(rest_time, announce: :new_day)
    end
    table_changed # everyone's HP back, in one update_all
  end

  def rested?(character)
    character.current_hp == character.stats["max_hp"] && character.current_mp == character.stats["max_mp"]
  end

  # The inn where the party is, if it's in a town with one open.
  def inn_here
    place = current_node&.location
    return unless place&.town? && !(place.respond_to?(:service_closed?) && place.service_closed?("inn"))

    place.view.fetch("services", []).find { |s| s["kind"] == "inn" }
  end

  # Making camp is for the road: in a town the party takes rooms.
  def rest!
    raise Refusal, "Not while a battle is on" if battle_on?
    raise Refusal, "The party is in #{current_node.name}: take rooms at #{inn_here['name']} instead. Camp is for the road." if inn_here

    transaction do
      # A night on the ground mends the body, but only half the mind: a full
      # night's MP takes a bed (the inn). Like a bed, it raises nobody.
      standing, fallen = characters.partition(&:conscious?)
      standing.each do |character|
        mp = [ character.current_mp + (character.stats["max_mp"] / 2), character.stats["max_mp"] ].min
        character.update!(hp: nil, mp: mp == character.stats["max_mp"] ? nil : mp, field_used: false)
      end
      fallen.each { |character| character.update!(field_used: false) }
      line = narrate(camp_line(fallen)).body
      tick_clocks!("rest")
      pass_time!(rest_time, announce: :new_day)
      line
    end
  end

  # What the party hears when it makes camp.
  def camp_line(fallen = characters.reject(&:conscious?))
    line = "The party rests. #{fallen.any? ? 'Everyone standing' : 'Everyone'} is back to full #{world.word('hp')}, and half their #{world.word('mp')}."
    fallen.any? ? "#{line} #{fallen.map(&:name).to_sentence} #{fallen.one? ? 'is' : 'are'} still down. #{raising_help}".strip : line
  end

  private

  # What does help the fallen, in this setting's words: "It takes a temple or Phoenix Down."
  def raising_help
    helps = []
    helps << "a bed at #{world.word('service.inn').downcase_first == 'inn' ? 'an inn' : "a #{world.word('service.inn').downcase_first}"}" if world.service_offered?("inn")
    helps << "a #{world.word('service.temple').downcase_first}" if world.service_offered?("temple")
    helps.concat(world.items.select { |item| item.consumable? && Battle::State.revives?(item.to_engine(1)) }.map(&:name))
    helps.any? ? "It takes #{helps.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}." : ""
  end

  # What the table hears when a service is paid for.
  def service_line(kind, character, service, by, cost, rumour = nil, down: false)
    payer = by == character.name ? character.name : "#{by}, for #{character.name},"
    case kind
    when "inn"
      "#{payer} takes a room at #{service['name']} (#{cost.zero? ? 'on the house' : money(cost)}). " \
        "#{character.name} is #{down ? 'back on their feet' : 'rested'}: full #{world.word('hp')} and #{world.word('mp')}."
    when "temple" then "#{payer} pays #{money(cost)} at #{service['name']}. #{character.name} is raised, whole again."
    when "guild"
      bought = "#{payer} buys a rumour at #{service['name']} (#{money(cost)})."
      if rumour
        rumour.update!(heard: true)
        "#{bought} “#{rumour.body}”"
      else
        "#{bought} The GM owes #{character.name} something true."
      end
    end
  end
end
