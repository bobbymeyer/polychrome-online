# frozen_string_literal: true

# The game noticing who the characters are (docs/STORY.md, item 2): their
# home town and their ties to the campaign's people come up in play, not
# only in the language model's prompts. Arriving (Campaign::Happenings,
# "arrive"): coming home is said at the table.
# A tie is whispered to its player (and so the GM) when the tied NPC is
# where the party arrives, or first speaks in a session; once a session.
module Campaign::Belonging
  extend ActiveSupport::Concern

  # Arriving at a place: who's home, and who they're tied to that lives here.
  def arrive_among_their_own!(node)
    home = characters.where(home_node: node).order(:created_at).map(&:name)
    narrate("#{home.to_sentence} #{home.one? ? 'is' : 'are'} home.") if home.any?
    return unless node.location

    npcs.where(location: node.location).find_each { |npc| remind_ties!(npc) }
  end

  # Each character tied to this NPC hears it, unless they did this session.
  def remind_ties!(npc)
    characters.order(:created_at).each do |character|
      tie = character.ties.find { |t| t["npc_id"] == npc.id } or next
      line = "#{TIE_PREFIX}#{npc.name}: #{tie['text']}"
      next if reminded?(character, npc)

      messages.create!(body: line, scope: "whisper", recipient: character)
    end
  end

  TIE_PREFIX = "Your tie to "

  private

  def reminded?(character, npc)
    messages.where(scope: "whisper", speaker: nil, recipient: character, created_at: Recap::BREAK.ago..)
            .where("body LIKE ?", "#{TIE_PREFIX}#{Message.sanitize_sql_like(npc.name)}:%").exists?
  end
end
