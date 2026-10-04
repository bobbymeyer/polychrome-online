# frozen_string_literal: true

# A road bends through waypoints to follow the picture it's drawn on
# (WorldRoute, MapEdge): [[x, y], ...] between its two ends, in the map's
# space (MapNode::WIDTH × MapNode::HEIGHT), in order from the from-end.
module RoadBends
  extend ActiveSupport::Concern

  MAX_WAYPOINTS = 12

  included do
    validate :waypoints_are_points
  end

  def waypoints=(rows)
    rows = rows.is_a?(Hash) ? rows.values : Array(rows)
    super(rows.filter_map do |row|
      pair = row.is_a?(Hash) ? [ row["x"] || row[:x], row["y"] || row[:y] ] : Array(row).first(2)
      next if pair.size < 2 || pair.any? { |v| v.to_s.strip.empty? }

      [ pair[0].to_i.clamp(0, MapNode::WIDTH), pair[1].to_i.clamp(0, MapNode::HEIGHT) ]
    end.first(MAX_WAYPOINTS))
  end

  # The points the road is drawn through, end to end: [[x, y], ...].
  def points
    [ [ road_from.x, road_from.y ] ] + waypoints + [ [ road_to.x, road_to.y ] ]
  end

  # A new bend where the road passes nearest to (x, y), kept in order.
  def bend_at(x, y)
    pts = points
    nearest = (0...pts.size - 1).min_by { |i| distance_to_segment([ x, y ], pts[i], pts[i + 1]) }
    self.waypoints = waypoints.dup.insert(nearest, [ x, y ])
  end

  private

  def distance_to_segment(p, a, b)
    px, py = p
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    length2 = (dx * dx) + (dy * dy)
    t = length2.zero? ? 0 : (((px - ax) * dx) + ((py - ay) * dy)) / length2.to_f
    t = t.clamp(0, 1)
    Math.hypot(px - (ax + (t * dx)), py - (ay + (t * dy)))
  end

  def waypoints_are_points
    errors.add(:waypoints, "must be points on the map") unless waypoints.is_a?(Array) && waypoints.all? { |pt| pt.is_a?(Array) && pt.size == 2 }
  end
end
