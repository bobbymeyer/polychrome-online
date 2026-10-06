# frozen_string_literal: true

# Request specs read the page they got back as a document, and sit down at
# a table the way the controllers do.
module RequestPages
  # The last response, parsed (Nokogiri). Rails parses an HTML response
  # itself; a Turbo Stream or a fragment is parsed here.
  def page
    body = response.parsed_body
    body.is_a?(Nokogiri::XML::Node) ? body : Nokogiri::HTML5.fragment(body.to_s)
  end

  # Take a seat at a campaign's table: "gm", a character (or its id), or
  # nil to stand up.
  def sit(campaign, seat)
    return delete campaign_table_seat_path(campaign) if seat.nil?

    post campaign_table_seat_path(campaign), params: { seat: seat.respond_to?(:id) ? seat.id : seat }
  end

  # Take a seat in a battle: "gm", or a party unit's id.
  def sit_in_battle(battle, seat)
    post battle_seat_path(battle), params: { seat: seat }
  end

  # Sit down, then look at the table.
  def at_the_table(campaign, as:)
    sit(campaign, as)
    get campaign_table_path(campaign)
  end
end

RSpec.configure do |config|
  config.include RequestPages, type: :request
end
