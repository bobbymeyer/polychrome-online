# frozen_string_literal: true

module Story
  # When a row fits, and what it remembers, in a few words a writer types:
  #
  #   when: "town, night, !smoke_seen, hurt >= 2, place = Hollin"
  #   sets: "smoke_seen, visits + 1, mood = grim"
  #
  # A bare key holds when its fact is true (or a number other than 0, or any
  # words but "no"); "!key" (or "not key") when it isn't, or isn't there.
  # Compared facts are numbers (= != > >= < <=) or words (= !=, any case).
  # Keys are written as flags are: lowercase, words joined by "_".
  module Criteria
    Condition = Data.define(:key, :op, :value) do
      def holds?(facts)
        fact = facts[key]
        case op
        when "?" then Criteria.truthy?(fact)
        when "!" then !Criteria.truthy?(fact)
        when "=" then Criteria.same?(fact, value)
        when "!=" then !Criteria.same?(fact, value)
        else
          number = Criteria.number(fact)
          !number.nil? && number.public_send(op, value.to_i)
        end
      end

      def to_s
        case op
        when "?" then key
        when "!" then "!#{key}"
        else "#{key} #{op} #{value}"
        end
      end
    end

    # A write-back: set a key ("=", "yes" when no value is given) or count it
    # up or down ("+", "-").
    Write = Data.define(:key, :op, :value)

    KEY = /[a-z][a-z0-9_]*/
    COMPARED = /\A(#{KEY})\s*(!=|>=|<=|=|>|<)\s*(.+)\z/
    NUMBERED = %w[> >= < <=].freeze
    FALSE_WORDS = %w[no false 0].freeze

    module_function

    # [conditions, problems] from a row's "when".
    def parse(text)
      problems = []
      conditions = split(text).filter_map do |part|
        condition(part) || (problems << "“#{part}” isn't something a row can ask: try town, !night, hurt >= 2 or place = Hollin" and nil)
      end
      [ conditions, problems ]
    end

    # [writes, problems] from a row's "sets".
    def parse_writes(text)
      problems = []
      writes = split(text).filter_map do |part|
        write(part) || (problems << "“#{part}” isn't something a row can remember: try smoke_seen, visits + 1 or mood = grim" and nil)
      end
      [ writes, problems ]
    end

    def split(text)
      text.to_s.split(/[,;\n]/).map(&:strip).reject(&:empty?)
    end

    def condition(part)
      part = part.downcase
      if (m = part.match(/\A(?:!|not\s+)\s*(#{KEY})\z/)) then Condition.new(key: m[1], op: "!", value: nil)
      elsif part.match?(/\A#{KEY}\z/) then Condition.new(key: part, op: "?", value: nil)
      elsif (m = part.match(COMPARED))
        value = m[3].strip
        return nil if NUMBERED.include?(m[2]) && !value.match?(/\A-?\d+\z/)

        Condition.new(key: m[1], op: m[2], value: value)
      end
    end

    def write(part)
      if (m = part.match(/\A(#{KEY})\z/i)) then Write.new(key: m[1].downcase, op: "=", value: "yes")
      elsif (m = part.match(/\A(#{KEY})\s*([+-])\s*(\d+)\z/i)) then Write.new(key: m[1].downcase, op: m[2], value: m[3].to_i)
      elsif (m = part.match(/\A(#{KEY})\s*=\s*(.+)\z/i)) then Write.new(key: m[1].downcase, op: "=", value: m[2].strip)
      end
    end

    # What a key holds after a write ({ "key", "op", "value" }), from what
    # it held: counting starts from 0, and anything not a number counts as 0.
    def written(write, was)
      case write["op"]
      when "+" then ((number(was) || 0) + write["value"].to_i).to_s
      when "-" then ((number(was) || 0) - write["value"].to_i).to_s
      else write["value"].to_s
      end
    end

    def truthy?(fact)
      case fact
      when nil, false then false
      when Integer then !fact.zero?
      when String then !fact.strip.empty? && !FALSE_WORDS.include?(fact.strip.downcase)
      else true
      end
    end

    def same?(fact, value)
      return false if fact.nil?

      fact.to_s.strip.casecmp?(value.to_s.strip)
    end

    def number(fact)
      case fact
      when Integer then fact
      when String then fact.strip.match?(/\A-?\d+\z/) ? fact.to_i : nil
      when true then 1
      end
    end
  end
end
