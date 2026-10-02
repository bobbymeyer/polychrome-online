# frozen_string_literal: true

module Story
  # What a table of story rows covers (docs/STORY.md, Later: the coverage
  # page; Short's "write the missing line", Compton's possibility space):
  # the matcher run over many moments, not one. Pure, like the report it
  # grew from (Generators::Report).
  #
  #   Coverage.run(rows, moments)
  #     # => { "moments", "empty" => [moments nothing fits],
  #     #      "rows" => [{ "fits", "wins", "beaten_by" }], one per row }
  #   Coverage.slots(moments, empty) { |facts| "town · night" }
  #   Coverage.rank(rows, facts)  # every row that fits, the best first
  module Coverage
    module_function

    def run(rows, moments, avoid: [])
      stats = rows.map { { "fits" => 0, "wins" => 0, "beaten_by" => Hash.new(0) } }
      empty = []
      moments.each do |facts|
        fitting = Matcher.candidates(rows, facts, avoid: avoid)
        if fitting.empty?
          empty << facts
          next
        end

        top = fitting.map { |c| c[:score] }.max
        winners = fitting.select { |c| c[:score] == top }
        fitting.each do |c|
          i = rows.index { |row| row.equal?(c[:row]) }
          stats[i]["fits"] += 1
          if winners.include?(c)
            stats[i]["wins"] += 1 # a tie shares the win: any of them can come up
          else
            winners.each { |w| stats[i]["beaten_by"][rows.index { |row| row.equal?(w[:row]) }] += 1 }
          end
        end
      end
      { "moments" => moments.size, "empty" => empty, "rows" => stats }
    end

    # { slot => [moments in it, how many nothing fits] }, the emptiest first.
    def slots(moments, empty, &slot)
      all = moments.group_by(&slot).transform_values(&:size)
      none = empty.group_by(&slot).transform_values(&:size)
      all.to_h { |label, n| [ label, [ n, none.fetch(label, 0) ] ] }
         .sort_by { |label, (n, missing)| [ -missing.fdiv(n), label.to_s ] }.to_h
    end

    # Every row that fits these facts, the most specific first:
    # [{ "row", "index", "score" }].
    def rank(rows, facts, avoid: [])
      Matcher.candidates(rows, facts, avoid: avoid)
             .map { |c| { "row" => c[:row], "index" => rows.index { |row| row.equal?(c[:row]) }, "score" => c[:score] } }
             .sort_by { |c| [ -c["score"], c["index"] ] }
    end

    # The keys a table's rows ask about, with the words and numbers they
    # compare them to: { key => { "values" => [...], "numbers" => bool } }.
    def asked(rows)
      rows.each_with_object({}) do |row, asked|
        conditions, = Criteria.parse(row["when"])
        conditions.each do |c|
          entry = (asked[c.key] ||= { "values" => [], "numbers" => false })
          if Criteria::NUMBERED.include?(c.op) then entry["numbers"] = true
          elsif c.value then entry["values"] |= [ c.value ]
          end
        end
        Matcher.slots(row["text"]).each { |key| asked[key] ||= { "values" => [], "numbers" => false } }
      end
    end
  end
end
