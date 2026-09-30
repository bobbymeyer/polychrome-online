# frozen_string_literal: true

# Making camp, and every night's sleep (#sleep!). A town's inn, temple and
# guild are the town's (Location::Town#services_for): in a town the party
# takes rooms at the inn, which rests everyone, the KO'd too; on the road it
# makes camp, which raises nobody.
module Campaign::Services
  extend ActiveSupport::Concern

  # What a night at camp gives back of MP (Outcome "rest").
  CAMP_MP = 50

  # Making camp: anywhere there's no inn to take rooms at.
  def camp_pastime
    Pastime.new(name: "Make camp", takes: 0, outcomes: [ Outcome.of("rest", CAMP_MP) ], service: "camp")
  end

  # The inn where the party is, if it's in a town with one open.
  def inn_here = current_node&.location&.inn

  # A night's sleep (Outcome "rest"), and the only one. In a bed, everyone
  # is rested, the KO'd too; at camp, those standing get full HP and a
  # share of MP, and the KO'd stay down. Field abilities come back, the
  # rest happens (Campaign::Happenings) and the night passes. Returns what the table heard.
  def sleep!(bed: false, mp_share: CAMP_MP)
    standing, fallen = characters.order(:created_at).partition(&:conscious?)
    if bed
      characters.each { |c| c.update!(hp: nil, mp: nil, field_used: false) }
    else
      standing.each do |c|
        mp = [ c.current_mp + (c.stats["max_mp"] * mp_share / 100), c.stats["max_mp"] ].min
        c.update!(hp: nil, mp: mp == c.stats["max_mp"] ? nil : mp, field_used: false)
      end
      fallen.each { |c| c.update!(field_used: false) }
    end
    line = narrate(bed ? bed_line(fallen) : camp_line(fallen, mp_share)).body
    happen!("rest") # the day's work pays off, the rest clocks tick
    pass_time!(rest_time, announce: :new_day)
    table_changed # everyone's HP back
    line
  end

  # What the party hears when it makes camp.
  def camp_line(fallen = characters.reject(&:conscious?), mp_share = CAMP_MP)
    share = mp_share == 50 ? "half their" : "#{mp_share}% of their"
    line = "The party rests. #{fallen.any? ? 'Everyone standing' : 'Everyone'} is back to full #{world.word('hp')}, and #{share} #{world.word('mp')}."
    fallen.any? ? "#{line} #{fallen.map(&:name).to_sentence} #{fallen.one? ? 'is' : 'are'} still KO'd. #{raising_help}".strip : line
  end

  private

  def bed_line(fallen)
    line = "Everyone sleeps in a bed: full #{world.word('hp')} and #{world.word('mp')}."
    fallen.any? ? "#{line} #{fallen.map(&:name).to_sentence} #{fallen.one? ? 'is' : 'are'} back on their feet." : line
  end

  # What does help the fallen, in this setting's words: "It takes a temple or Phoenix Down."
  def raising_help
    helps = []
    helps << "a bed at #{world.word('service.inn').downcase_first == 'inn' ? 'an inn' : "a #{world.word('service.inn').downcase_first}"}" if world.service_offered?("inn")
    helps << "a #{world.word('service.temple').downcase_first}" if world.service_offered?("temple")
    helps.concat(world.items.select { |item| item.consumable? && Battle::State.revives?(item.to_engine(1)) }.map(&:name))
    helps.any? ? "It takes #{helps.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}." : ""
  end
end
