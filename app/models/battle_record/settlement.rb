# frozen_string_literal: true

# When the battle ends, what happened is written back to the campaign:
# HP/MP always; on victory, EXP split among the standing, ABP to each
# standing character's current job, gil, and the dropped items. Stolen items
# are the party's however the battle ends. Antagonists who got away come
# back stronger. Runs once, inside the transaction of the action that ended
# the battle.
module BattleRecord::Settlement
  extend ActiveSupport::Concern

  # What the GM made of a wipe (Campaign::Defeat#recover!), told to
  # everyone still looking at the results.
  def aftermath!(line)
    update!(settlement: (settlement || {}).merge("aftermath" => line))
    broadcast_replace_to self, target: "battle_aftermath", partial: "battles/panels/aftermath", locals: { battle: self }
  end

  private

  def settle!(events)
    return if settlement

    characters = characters_by_unit
    party.each do |unit|
      characters[unit["id"]]&.update!(hp: unit["hp"], mp: unit["mp"])
    end

    summary = { "result" => status, "gil" => 0, "drops" => [], "members" => [], "used" => use_up_items!,
                "stolen" => take_stolen_items!, "antagonists" => settle_antagonists! }.compact
    victory = events.find { |e| e["type"] == "victory" }
    standing = party.select { |u| u["hp"].positive? }.filter_map { |u| characters[u["id"]] }
    if victory
      rewards = victory["rewards"]
      exp_share = standing.empty? ? 0 : rewards["exp"].to_i / standing.size
      standing.each do |character|
        summary["members"] << { "name" => character.name }.merge(character.gain!(exp: exp_share, abp: rewards["abp"].to_i))
      end

      campaign.increment!(:gil, rewards["gil"].to_i)
      summary["gil"] = rewards["gil"].to_i
      items = world.items.where(slug: victory["drops"]).index_by(&:slug)
      victory["drops"].each do |slug|
        next unless (item = items[slug])

        campaign.add_item!(item)
        summary["drops"] << item.name
      end
    end
    update!(settlement: summary)
    announce!(settlement_line(summary))
    # The room this fight was for is dealt with now, and only now: lost or
    # fled, what waits there waits still (Location::Exploration#cleared?).
    campaign.dungeon_in_progress&.resolve!(room) if victory && room
    record_deeds!(summary, characters) if victory
    # Everyone down: what now is the table's to decide (Campaign::Defeat).
    campaign.ask_what_now! if status == "defeat" && campaign.wiped_out?
  end

  # Stolen items: the party's however it ended. Returns their names.
  def take_stolen_items!
    items = world.items.where(slug: state.fetch("stolen", [])).index_by(&:slug)
    state.fetch("stolen", []).filter_map do |slug|
      next unless (item = items[slug])

      campaign.add_item!(item)
      item.name
    end
  end

  # Antagonists who got away come back stronger; the fallen are finished.
  # Returns [{ "name", "fate" }] for the settlement, or nil if none fought.
  def settle_antagonists!
    fates = state["units"].filter_map do |unit|
      npc = (id = Npc.from_battle_unit(unit["id"])) && campaign.npcs.find_by(id: id)
      next unless npc

      fate = if unit["gone"] then "escaped"
      elsif unit["hp"].zero? && first_meeting?(npc) then "slipped_away"
      elsif unit["hp"].zero? then "defeated"
      else "remains"
      end
      if %w[escaped slipped_away].include?(fate)
        # Gone from here, to turn up somewhere near (Campaign::Overnight).
        npc.update!(escapes: npc.escapes + 1, location: campaign.current_node&.location || npc.location)
      end
      npc.update!(defeated_at: Time.current) if fate == "defeated"
      { "name" => npc.name, "fate" => fate }
    end
    fates.presence
  end

  # The setting's villains aren't finished the first time the party puts
  # them down: they slip away, to come back stronger (the story needs them
  # again). The second time, down is down.
  def first_meeting?(npc)
    npc.world_figure_id.present? && npc.escapes.zero?
  end

  # Items used in battle come out of the bag. Returns { "Potion" => 2 }.
  def use_up_items!
    carried = initial_state.fetch("items", {})
    return {} if carried.empty?

    items = world.items.where(slug: carried.keys).index_by(&:slug)
    carried.each_with_object({}) do |(slug, item), used|
      n = item["count"] - state.dig("items", slug, "count").to_i
      next unless n.positive? && items[slug]

      campaign.use_items!(items[slug], n)
      used[item["name"]] = n
    end
  end

  def settlement_line(summary)
    parts = [ { "victory" => "Victory!", "defeat" => "The party has fallen.", "fled" => "The party got away." }.fetch(summary["result"], "It's over.") ]
    if boss? && summary["result"] == "victory" && summary["antagonists"].blank?
      names = boss_names
      parts << "#{names.to_sentence} #{names.size > 1 ? 'have' : 'has'} fallen!"
    end
    Array(summary["antagonists"]).each do |antagonist|
      case antagonist["fate"]
      when "escaped" then parts << "#{antagonist['name']} got away, and will be back stronger."
      when "slipped_away" then parts << "#{antagonist['name']} falls, and when the dust settles is gone. This isn't over."
      when "defeated" then parts << "#{antagonist['name']} is finished."
      end
    end
    parts << "Stole #{summary['stolen'].to_sentence}." if summary["stolen"].present?
    parts << "Used #{summary['used'].map { |name, n| "#{n} × #{name}" }.to_sentence}." if summary["used"].present?
    parts << "#{campaign.money(summary['gil'])}." if summary["gil"].positive?
    parts << "Found #{summary['drops'].to_sentence}." if summary["drops"].any?
    summary["members"].each do |member|
      parts << "#{member['name']} reached level #{member['level'].last}." if member["level"]
      parts << "#{member['name']} learned #{member['learned'].to_sentence}." if member["learned"].any?
    end
    "#{name}: #{parts.join(' ')}"
  end

  # What people will say about it (Campaign::Deeds): an antagonist beaten for
  # good, or a dungeon's master fallen.
  def record_deeds!(summary, characters)
    party = campaign.party_names(characters.values.sort_by(&:created_at))
    Array(summary["antagonists"]).select { |a| a["fate"] == "defeated" }.each do |antagonist|
      campaign.record_deed!("#{party} defeated #{antagonist['name']} for good.", sway: 1, kind: "antagonist")
    end
    dungeon = campaign.dungeon_in_progress
    return unless boss? && dungeon

    campaign.record_deed!("#{party} cleared #{dungeon.name}.", sway: 1, kind: "cleared")
    campaign.clear_place!(campaign.current_node)
  end
end
