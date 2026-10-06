# frozen_string_literal: true

require "csv"

# The battle reports (Battle::Report) as CSV for a spreadsheet, a table a
# file: a battle's fighters, rounds and moves; a campaign's battles,
# fighters and moves. The columns are the pages' own, in the world's words
# for HP and MP, and the numbers stay numbers.
module BattleReportCsv
  BATTLE_TABLES = %w[fighters rounds moves].freeze
  CAMPAIGN_TABLES = %w[battles fighters moves].freeze
  SIDES = { "party" => "Party", "enemy" => "Enemy" }.freeze

  module_function

  # One battle's table (Battle::Report.build).
  def battle(report, world, table:)
    case table
    when "rounds"
      table([ "Round", "The party dealt", "The enemies dealt" ], report["by_round"].map { |round| round.values_at("round", "party", "enemy") })
    when "moves" then moves(report["moves"])
    else
      hp, mp = world.word("hp"), world.word("mp")
      table([ "Side", "Who", "Kind", "Dealt", "Taken", "Healed", "KOs", "Went down", "Actions", "Misses", "Crits", "#{mp} spent", "#{hp} left", "Max #{hp}", "Used" ],
            report["units"].map do |unit|
              [ SIDES[unit["side"]], unit["name"], unit["kind_name"], *unit.values_at(*%w[dealt taken healed kos downed actions misses crits mp_spent hp max_hp]),
                unit["abilities"].map { |name, count| "#{name} ×#{count}" }.join(", ") ]
            end)
    end
  end

  # One of a campaign's tables (Battle::Report.across).
  def campaign(across, world, table:)
    case table
    when "fighters"
      table([ "Side", "Who", "Battles", "Faced", "Dealt", "Dealt a battle", "Dealt an action", "Taken", "Healed", "KOs", "Went down",
              "Actions", "Misses", "Crits", "#{world.word('mp')} spent" ],
            across["fighters"].map do |fighter|
              [ SIDES[fighter["side"]], fighter["name"], *fighter.values_at(*%w[battles units dealt dealt_per_battle dealt_per_action taken healed kos downed actions misses crits mp_spent]) ]
            end)
    when "moves" then moves(across["moves"])
    else
      table([ "Battle", "Fought", "Result", "Boss", "Rounds", "Turns", "Party dealt", "Party took", "Party healed", "Party down", "Enemies down", "Against" ],
            across["battles"].map do |battle|
              [ battle["name"], battle["fought_on"]&.iso8601, battle["result"] == "input" ? "Under way" : battle["result"].to_s.humanize, battle["boss"] ? "Yes" : "No",
                *battle.values_at(*%w[rounds turns party_dealt party_taken party_healed party_downed enemies_downed]),
                battle["foes"].map { |name, count| count > 1 ? "#{count} × #{name}" : name }.join(", ") ]
            end)
    end
  end

  def moves(moves)
    table([ "Side", "Move", "Uses", "Dealt", "Dealt a use", "Healed" ],
          moves.map { |move| [ SIDES[move["side"]], move["name"], *move.values_at("uses", "dealt", "dealt_per_use", "healed") ] })
  end

  def table(headers, rows)
    CSV.generate { |csv| ([ headers ] + rows).each { |row| csv << row } }
  end
end
