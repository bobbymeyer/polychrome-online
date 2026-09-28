# frozen_string_literal: true

# Who they are in the setting: where they're from (an origin, good for a
# skill) and their ties to the campaign's people.
module Character::Background
  extend ActiveSupport::Concern

  # Points on a check with this skill (World#skills): the current job's
  # bonus, if it's good at it.
  # The job's bonus, and the origin's if it's this skill.
  def skill_bonus(slug)
    (job.skills.include?(slug.to_s) ? Job::SKILL_BONUS : 0) + (origin_entry&.dig("skill") == slug.to_s ? World::ORIGIN_BONUS : 0)
  end

  def origin_entry
    campaign.world.origin(origin) if origin
  end

  # [{ "npc_id", "text" }] from form rows: blanks dropped, only the
  # campaign's NPCs.
  def ties=(value)
    rows = value.is_a?(Hash) ? value.values : Array(value)
    super(rows.filter_map do |row|
      row = row.to_h.stringify_keys
      text = row["text"].to_s.strip
      next if text.empty?

      { "npc_id" => row["npc_id"].presence&.to_i, "text" => text.truncate(200) }.compact
    end.first(6))
  end

  # "Owes Mara Vell money", with who it's about.
  def tie_lines
    npcs = campaign.npcs.where(id: ties.filter_map { |t| t["npc_id"] }).index_by(&:id)
    ties.map { |t| [ npcs[t["npc_id"]], t["text"] ] }
  end

  private

  def from_the_setting
    errors.add(:origin, "isn't one of #{campaign.world.name}'s") if origin.present? && !origin_entry
    errors.add(:home_node, "isn't on this campaign's map") if home_node && home_node.campaign_id != campaign_id
  end
end
