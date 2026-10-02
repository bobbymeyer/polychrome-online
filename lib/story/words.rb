# frozen_string_literal: true

module Story
  # The word check against a table's lines and veils (ch. 5): a row that
  # names one never comes up. A line is named when every word in it that
  # carries meaning is in the row ("harm to children" needs harm and
  # children; "spiders" is named by "a spider"), so a row can't say a veil
  # by accident, and plain words like "to" never rule a row out.
  module Words
    LIGHT = %w[a an and any at by for from in into of off on or the to with without no not all].freeze

    module_function

    # The first of `limits` the text names, or nil.
    def clash(text, limits)
      said = words(text)
      Array(limits).find do |limit|
        needed = words(limit) - LIGHT
        needed.any? && needed.all? { |word| said.include?(word) }
      end
    end

    def words(text)
      text.to_s.downcase.scan(/[a-z0-9']+/).map { |word| stem(word.delete("'")) }.uniq
    end

    # Plurals folded, roughly: spiders, spider; flies, fly.
    def stem(word)
      return word if word.length < 4
      return "#{word[0..-4]}y" if word.end_with?("ies")
      return word[0..-2] if word.end_with?("s") && !word.end_with?("ss")

      word
    end
  end
end
