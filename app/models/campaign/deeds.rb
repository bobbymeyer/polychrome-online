# frozen_string_literal: true

# What the party does becomes part of the world. A deed is a rumour
# (Rumour#deed) told from where it happened, carrying its sway: every town
# the news reaches thinks a little better, or worse, of the party
# (Location::Town#reputation). The
# party hears about themselves on arriving somewhere the story got to
# first. Beating an antagonist for good and clearing a dungeon are deeds
# by themselves; the GM records the rest.
module Campaign::Deeds
  extend ActiveSupport::Concern

  # seen: the party is there, and already knows (a town's thanks).
  def record_deed!(body, at: current_node, sway: 0, kind: "gm", seen: false)
    start_rumour!(body, at: at, sway: sway.to_i, deed: kind, seen: seen)
  end

  # What the party did, as a rumour each (striking one takes its story back).
  def deeds = rumours.deeds

  # A dungeon's boss is beaten: the table hears it, with a fanfare, and the
  # world answers. The clocks the place was behind stop, unless the one
  # behind them got away (Npc, first meeting): their trouble goes on. The
  # roads out of it quieten; what the place was hiding comes out; and the
  # nearest town waits to welcome the party back.
  def clear_place!(node)
    return unless node

    narrate("#{node.name} is cleared!", cue: "cleared")
    node.clocks.running.each(&:stop!) unless node.location && npcs.at_large.exists?(location_id: node.location.id)
    calm_roads!(node)
    bring_to_light!(node)
    expect_welcome!(node)
  end

  # Back in the town that was waiting for news: someone who lives there says
  # so, and the town thinks well of the party for it (a deed there, so its
  # prices come down: Location::Town#price_here), and whoever has something
  # on their mind tells them (a hook for what's next).
  def welcome_back!(node)
    place = welcomes[node.id.to_s] or return
    folk = node.location&.town? ? node.location.townsfolk : []
    host = folk.find { |f| f["service"] == "inn" } || folk.first
    transaction do
      update!(welcomes: welcomes.except(node.id.to_s))
      messages.create!(body: "#{host ? host['name'] : 'The whole street'} meets the party: “You cleared #{place}? " \
                             "Then you've friends in #{node.name}, and friends pay less.”")
      record_deed!("#{node.name} is grateful for #{place}", at: node, sway: 2, kind: "cleared", seen: true)
      hook = folk.find { |f| f != host && f["hook"].present? }
      messages.create!(body: "#{hook['name']}, #{hook['title'].downcase}: “#{hook['hook']}”") if hook
    end
  end

  # The names of those who did it: "Rook, Lenna and Faris".
  def party_names(characters = self.characters.order(:created_at))
    names = characters.map(&:name)
    names.empty? ? "The party" : names.to_sentence
  end

  private

  # Dangerous roads out of a cleared place are only as risky as any road.
  def calm_roads!(node)
    roads = map_edges.where(from_node: node).or(map_edges.where(to_node: node)).where(state: "dangerous")
    return if roads.none?

    roads.update_all(state: "open", updated_at: Time.current)
    narrate("The roads out of #{node.name} are quiet now.")
  end

  # What the place kept (a front's secrets about it, or about whoever held
  # it) is found there: the thread to pull next.
  def bring_to_light!(node)
    location = node.location or return
    kept = secrets.kept.where(location: location).or(secrets.kept.where(npc: npcs.where(location: location)))
    kept.order(:id).each { |secret| secret.reveal!(by: "In #{node.name}") }
  end

  def expect_welcome!(node)
    town = nearest_town(node) or return
    update!(welcomes: welcomes.merge(town.id.to_s => node.name)) unless town == node
  end
end
