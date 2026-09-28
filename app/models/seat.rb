# frozen_string_literal: true

# Where someone sits at a campaign's table or in a battle: the GM's seat, a
# character's, or nobody's (watching, or the shared screen).
#
# What a seat may see and do follows from it, so it's decided here and
# nowhere else: which lines it sees (#sees?, Message.visible_to), which
# private streams its page listens on, whose lines it may take back.
#
# The session remembers seats as strings ("gm", a character's id, a battle
# unit's id); TableSeat and BattleSeat check those against the account and
# hand out one of these. In a battle, a seat can be a party unit with no
# character behind it (a battle outside a campaign, a guest ally).
Seat = Data.define(:gm, :character, :unit_id) do
  def self.gm = new(gm: true, character: nil, unit_id: nil)
  def self.nobody = new(gm: false, character: nil, unit_id: nil)
  def self.of(character, unit_id: character&.battle_unit_id) = new(gm: false, character: character, unit_id: unit_id)

  def gm? = gm
  def character? = !character.nil?
  def seated? = gm? || character? || !unit_id.nil?

  def name = gm? ? "GM" : character&.name

  # The map as this seat may see it: the GM's shows what's hidden.
  def map_stream = gm? ? :map_gm : :map

  # Where what's said privately to this seat arrives: the GM's notes and
  # every whisper, or this character's whispers.
  def private_stream(campaign)
    if gm? then [ campaign, :gm ]
    elsif character? then [ character, :whispers ]
    end
  end

  def sees?(message)
    return true if gm?
    return false if message.gm_only?
    return true unless message.whisper?

    character? && character == message.whisper_character
  end

  # The GM takes back any line said at the table; a player their own. What
  # the game itself logged stays.
  def may_retract?(message)
    return false if message.system?

    gm? || (character? && message.speaker == character)
  end

  # Whose lines the page offers to take back (chat_line_controller).
  def retracts
    if gm? then "all"
    elsif character? then "Character:#{character.id}"
    end
  end
end
