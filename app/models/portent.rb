# frozen_string_literal: true

# A step on a clock's way to full (docs/STORY.md, item 8; Dungeon World's
# grim portents, ch. 20), each a little worse than the last, and the signs
# of it the party might see. Written one step per line, first segment
# first, each step's signs under it, as story rows (Story::Matcher):
#
#   The dockhands stop talking to strangers.
#   - Fresh brass paint on every warehouse door.
#   - A dockhand spits as {who} passes. | town
#   Ships start mooring elsewhere.
#   - Empty berths at {place}, and gulls with nothing to fight over. | town
#
# A step the GM hears when its segment fills (Clock#tick!); its signs may
# come up when the party arrives somewhere, more often as the clock fills
# (Campaign::Remarks#offer_sign!).
Portent = Data.define(:text, :signs)

class Portent
  SIGN = /\A[-*•]\s*/

  # [portents, problems] from a clock's text.
  def self.parse(text)
    portents = []
    problems = []
    text.to_s.lines.map(&:strip).reject(&:empty?).each do |line|
      if line.match?(SIGN)
        sign_text, condition = line.sub(SIGN, "").split(/\|(?![^{]*\})/, 2).map(&:strip)
        if portents.empty?
          problems << "“#{line.truncate(40)}” is a sign, but there's no step above it"
          next
        end
        row = { "text" => sign_text, "when" => condition.presence }.compact
        problems.concat(Story::Matcher.problems(row).map { |problem| "A sign of “#{portents.last.text.truncate(30)}”: #{problem}" })
        portents.last.signs << row
      else
        portents << new(text: line, signs: [])
      end
    end
    [ portents, problems ]
  end

  def self.list(text) = parse(text).first
end
