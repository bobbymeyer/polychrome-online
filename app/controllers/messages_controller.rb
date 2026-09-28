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
    return head :forbidden unless seat

    fields = params.expect(message: %i[body expression speaker whisper_to])
    @message = @campaign.messages.new(body: fields[:body], expression: fields[:expression])
    seat == "gm" ? as_gm(fields) : as_player(seat, fields)
    # The GM can put a choice to the table: "? Trust Cid | Refuse -> trusted_cid".
    if seat == "gm" && (choice = Message.parse_choice(fields[:body]))
      @message = Message.choice(@campaign, **choice)
    end

    if @message.save
      @refocus = true
      # Keep who's speaking and how; a whisper is one line, so "To" goes
      # back to everyone rather than silently staying private.
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
    seat = table_seat
    allowed = !@message.system? && (seat == "gm" || (seat.is_a?(Character) && @message.speaker == seat))
    return forbid("That line isn't yours to take back.") unless allowed

    @message.destroy!
    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_back_or_to campaign_table_path(@campaign), status: :see_other }
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
