class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include LocalCoop
  include TableSeat # your seat at a campaign's table, for the account menu on every page in it
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # The game said no: tell whoever asked, back where they were (else at the
  # table, when there is one). Controllers that know a better place to say
  # it (a prep anchor, the map's panel) rescue it themselves.
  rescue_from Refusal do |refusal|
    respond_to do |format|
      format.html { redirect_back_or_to(@campaign ? campaign_table_path(@campaign) : root_path, alert: refusal.message, status: :see_other) }
      format.any { head :unprocessable_content }
    end
  end
end
