# frozen_string_literal: true

# Archetypes pay off the time a party spends on things to do (Job#payoff),
# settled at the next rest: the campaign counts the parts of the day spent.
# The Base World's archetypes get their payoffs; other worlds set their own.
class AddPayoffsToJobs < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BASE = {
    "freelancer" => { "kind" => "money", "amount" => 20, "line" => "{who} picks up odd work: {amount}." },
    "knight" => { "kind" => "exp", "amount" => 20, "line" => "{who} drills with the watch: {amount}." },
    "thief" => { "kind" => "money", "amount" => 40, "line" => "{who} comes back with {amount} and no explanation." },
    "monk" => { "kind" => "exp", "amount" => 25, "line" => "{who} trains until it hurts: {amount}." },
    "black_mage" => { "kind" => "abp", "amount" => 2, "line" => "{who} studies by candlelight: {amount}." },
    "white_mage" => { "kind" => "rumour", "amount" => 1, "line" => "{who} sits with the sick, and hears something: {rumour}" },
    "red_mage" => { "kind" => "money", "amount" => 30, "line" => "{who} duels for a purse: {amount}." },
    "summoner" => { "kind" => "abp", "amount" => 2, "line" => "{who} talks with the small spirits: {amount}." },
    "geomancer" => { "kind" => "rumour", "amount" => 1, "line" => "{who} reads the land, and the land says: {rumour}" },
    "dragoon" => { "kind" => "exp", "amount" => 25, "line" => "{who} climbs the highest thing in sight: {amount}." }
  }.freeze

  def up
    add_column :jobs, :payoff, :json, default: {}, null: false
    add_column :campaigns, :spent_parts, :integer, default: 0, null: false
    base = select_value("SELECT id FROM worlds WHERE slug = 'base'")
    return unless base

    BASE.each do |slug, payoff|
      execute "UPDATE jobs SET payoff = #{connection.quote(payoff.to_json)} WHERE world_id = #{base.to_i} AND slug = #{connection.quote(slug)}"
    end
  end

  def down
    remove_column :campaigns, :spent_parts
    remove_column :jobs, :payoff
  end
end
