# frozen_string_literal: true

# A campaign's invite code is made when the campaign is (Campaign), not the
# first time a page shows it: give the ones that don't have one theirs.
class GiveEveryCampaignAJoinCode < ActiveRecord::Migration[8.1]
  def up
    select_values("SELECT id FROM campaigns WHERE join_code IS NULL").each do |id|
      execute "UPDATE campaigns SET join_code = #{quote(SecureRandom.alphanumeric(6).upcase)} WHERE id = #{Integer(id)}"
    end
  end

  def down; end
end
