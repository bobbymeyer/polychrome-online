# frozen_string_literal: true

module MapsHelper
  LABEL_BELOW = 38
  LABEL_ABOVE = -24
  LABEL_HEIGHT = 26
  LABEL_CHAR_WIDTH = 12 # a rough width per letter at the map's label size

  PHONE_CHAR_WIDTH = 21 # the same, at the bigger size a phone draws names (stage.css)

  # Which way a place's name runs on a phone, where names are drawn bigger:
  # from the place, inward, when centred it would run off the map's edge
  # ("is-left": a place near the left edge). Nil when it fits centred.
  def map_label_side(node)
    half = node.name.length * PHONE_CHAR_WIDTH / 2
    if node.x - half < 0 then "is-left"
    elsif node.x + half > MapNode::WIDTH then "is-right"
    end
  end

  # Where each place's name goes on the map: under its marker, or over it
  # when the space under is taken by a name already placed (Varn and Goblin
  # Hollow side by side). { node_id => y offset }
  def map_label_offsets(nodes)
    placed = []
    nodes.to_h do |node|
      offset = [ LABEL_BELOW, LABEL_ABOVE ].find { |dy| placed.none? { |box| overlap?(box, label_box(node, dy)) } } || LABEL_BELOW
      placed << label_box(node, offset)
      [ node.id, offset ]
    end
  end

  private

  # The room a name takes, at the size a phone draws it (the larger of the
  # two), running the way it runs there: names that clear each other on a
  # phone clear each other everywhere.
  def label_box(node, dy)
    width = node.name.length * PHONE_CHAR_WIDTH
    top = node.y + dy - (LABEL_HEIGHT * PHONE_CHAR_WIDTH / LABEL_CHAR_WIDTH) + 6
    left = case map_label_side(node)
    when "is-left" then node.x - 24
    when "is-right" then node.x + 24 - width
    else node.x - width / 2
    end
    [ left, top, left + width, node.y + dy + 6 ]
  end

  def overlap?(a, b)
    a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3]
  end

  # A room's name on a floorplan, in the room's box: on up to three lines
  # ("Shuttered / Shopping / Street"), the last cut short only if it has to be.
  ROOM_LINE = 12 # letters that fit on a line of a room's box

  def room_name_lines(name)
    lines = name.to_s.split.each_with_object([ +"" ]) do |word, out|
      if out.last.empty? then out.last << word
      elsif out.last.length + 1 + word.length <= ROOM_LINE then out.last << " " << word
      else out << word.dup
      end
    end
    return lines if lines.size <= 3 && lines.all? { |line| line.length <= ROOM_LINE }

    (lines.first(2).map { |line| line.truncate(ROOM_LINE) } + [ lines.drop(2).join(" ").truncate(ROOM_LINE) ]).compact_blank
  end

  # One slice of the day clock (campaigns/tables/_day_clock), as an SVG path
  # on a 100 × 100 dial: the index-th of `count`, centred on its place round
  # the dial from the top, clockwise.
  def clock_slice(index, count, radius: 44)
    step = 360.0 / count
    from, to = [ index * step - step / 2, index * step + step / 2 ].map do |angle|
      rad = (angle - 90) * Math::PI / 180
      "#{(50 + radius * Math.cos(rad)).round(2)} #{(50 + radius * Math.sin(rad)).round(2)}"
    end
    "M50 50 L#{from} A#{radius} #{radius} 0 #{step > 180 ? 1 : 0} 1 #{to} Z"
  end
end
