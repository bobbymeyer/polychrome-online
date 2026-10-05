# frozen_string_literal: true

# Posting a line. Who it's from is decided here, from the seat, never from
# the params: players always speak as their own character, and only the GM
# seat can narrate or speak as an NPC (possession, §7).
class MessagesController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign, only: :create

  def create
    seat = table_seat
    return head :forbidden unless seat.seated?

    fields = params.expect(message: %i[body expression speaker whisper_to])
    @message = @campaign.messages.new(body: fields[:body], expression: fields[:expression])
    seat.gm? ? as_gm(fields) : as_player(seat.character, fields)
    # The GM can put a choice to the table: "? Trust Cid | Refuse -> trusted_cid".
    if seat.gm? && (choice = Message.parse_choice(fields[:body]))
      @message = Message.choice(@campaign, **choice)
    end

    if @message.save
      @refocus = true
      # Keep who's speaking and how; a whisper is one line, so it goes back
      # to everyone rather than silently staying private. The Narrator, once
      # chosen over the scene's speaker, stays until the scene moves on.
      @narrated = seat.gm? && @message.speaker.nil?
      @message = @campaign.messages.new(speaker: @message.speaker, expression: @message.expression)
      render "campaigns/composers/show", layout: false
    else
      render "campaigns/composers/show", layout: false, status: :unprocessable_content
    end
  end

  # Taking a line back: the GM any line said at the table, a player their
  # own. What the game itself logged (system lines) stays.
  def destroy
    @message = Message.find(params[:id])
    @campaign = @message.campaign
    return forbid("That line isn't yours to take back.") unless table_seat.may_retract?(@message)

    @message.destroy!
    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_back_or_to campaign_table_path(@campaign), status: :see_other }
    end
  end

  private

  # speaker: "narrator" or "npc:<id>" (the chip), unless the line starts with
  # a name and a colon ("Cid (happy): Hold on!", "Narrator: Wind."), read as
  # a script's line is (Scene.read_line); whisper_to: "" or a character id.
  def as_gm(fields)
    raw = fields[:body].to_s.strip
    line = Scene.read_line(raw, @campaign.npcs.to_a)
    if line["problem"].nil? && line["text"] != raw
      @message.body = line["text"]
      @message.speaker = line["speaker"]
      @message.expression = line["expression"] if line["expression"].present?
    elsif (npc_id = fields[:speaker].to_s[/\Anpc:(\d+)\z/, 1])
      @message.speaker = @campaign.npcs.find(npc_id)
    end
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
