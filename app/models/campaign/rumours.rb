# frozen_string_literal: true

# How news travels: a rumour starts somewhere on the map, travels a road a
# night (Campaign::Night), and the party hears whatever got to a place before
# them. A deed is a rumour too (Campaign::Deeds), and so is a secret that
# got out.
module Campaign::Rumours
  extend ActiveSupport::Concern

  # People start talking about something at a place on the map. seen: the
  # party was there and saw it happen, so there's nothing to hear. deed:
  # what kind, for something the party did (Campaign::Deeds); sway: a
  # deed's, moving each town's view of the party as the news gets there.
  def start_rumour!(body, at:, also: [], seen: false, sway: 0, deed: nil, secret: nil, about: nil)
    rumour = rumours.create!(body: body, origin: at, heard: seen, heard_day: (day if seen), heard_at: (at if seen),
                             day: day, sway: sway, deed: deed, secret: secret, about: about)
    rumour.reach!(([ at ] + also).compact, day: day)
    rumour
  end

  # What the party hears on reaching a place: every rumour that got there
  # before them. Only where there are people to talk to.
  def hear_rumours!(node = current_node)
    return [] unless node

    # Not their own deed where they did it: they were there.
    heard = rumours.travelling.unheard.at(node).where.not(id: rumours.deeds.where(origin: node).select(:id))
    # Somewhere nobody lives (a landmark, the wilds) only says what was set loose right there.
    heard = heard.where(origin: node) unless node.location
    heard.order(:id).each do |rumour|
      rumour.update!(heard: true, heard_day: day, heard_at: node)
      said = narrate(rumour.secret_id ? "In #{node.name}, someone whispers: “#{rumour.body}”" : "In #{node.name}, people are saying: “#{rumour.body}”")
      # A secret that got out is out: the party knows it now (the whisper was its telling).
      rumour.secret.update!(revealed_at: said.created_at, revealed_by: "Heard in #{node.name}") if rumour.secret && !rumour.secret.revealed?
      hear_of!(rumour)
    end
  end

  # A rumour that points somewhere puts the place on the map once it's heard
  # (Dragon Quest's townsfolk: "the cave north of here…").
  def hear_of!(rumour)
    place = rumour.about
    return unless place && !place.visible?

    place.update!(visible: true)
    narrate("#{place.name} is on the map now.")
  end

  # A rumour nobody at the table has heard yet (the guild sells one).
  def rumour_for_sale
    rumours.travelling.unheard.talk.order(:id).first
  end
end
