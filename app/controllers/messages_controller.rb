# frozen_string_literal: true

# Posting a line. Who it's from is decided here, from the seat, never from
# the params: players always speak as their own character, and only the GM
# seat can narrate or speak as an NPC (possession, §7).
class MessagesController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def create
    seat = table_seat
    return head :forbidden unless seat

    fields = params.expect(message: %i[body expression speaker whisper_to])
    @message = @campaign.messages.new(body: fields[:body], expression: fields[:expression])
    seat == "gm" ? as_gm(fields) : as_player(seat, fields)

    if @message.save
      @refocus = true
      # Keep who's speaking and how; a whisper is one line, so "To" goes
      # back to everyone rather than silently staying private.
      @message = @campaign.messages.new(speaker: @message.speaker, expression: @message.expression)
      render "composers/show", layout: false
    else
      render "composers/show", layout: false, status: :unprocessable_content
    end
  end

  private

  # speaker: "narrator" or "npc:<id>"; whisper_to: "" or a character id.
  def as_gm(fields)
    npc_id = fields[:speaker].to_s[/\Anpc:(\d+)\z/, 1]
    @message.speaker = @campaign.npcs.find(npc_id) if npc_id
    if fields[:whisper_to].present?
      @message.scope = "whisper"
      @message.recipient = @campaign.characters.find(fields[:whisper_to])
    end
  end

  # whisper_to: "gm" to whisper to the GM.
  def as_player(character, fields)
    @message.speaker = character
    @message.scope = "whisper" if fields[:whisper_to] == "gm"
  end
end
