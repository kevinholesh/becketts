# Blue Track Builder
# Builds a track path from a sequence of geometric primitives (arcs + straights)
# This allows the blue track to be defined independently of the original SVG

class BlueTrackBuilder
  # Points per inch for generated paths
  POINTS_PER_INCH = 5

  attr_reader :points, :path_length, :segments

  def initialize(definition, start_pt, start_dir)
    @definition = definition
    @start_pt = start_pt.dup
    @start_dir = normalize(start_dir)
    @points = []
    @segments = []  # Array of { index: N, type: :straight/:turn, points: [...] }
    @path_length = 0.0
  end

  # Build the track from the primitive definition
  # Returns array of points in racing order (entry to exit)
  def build
    @points = [@start_pt.dup]
    @segments = []
    current_pt = @start_pt.dup
    current_dir = @start_dir.dup
    @path_length = 0.0

    @definition.each_with_index do |prim, idx|
      case prim[:type]
      when :straight
        length = prim[:length] || 0
        next if length <= 0

        # Apply angle adjustment if specified
        if prim[:angle]
          # Absolute angle in degrees (0 = right, 90 = down in SVG coords)
          angle_rad = prim[:angle] * Math::PI / 180.0
          current_dir = [Math.cos(angle_rad), Math.sin(angle_rad)]
        elsif prim[:angle_offset]
          # Relative offset from current direction (positive = clockwise/right)
          current_dir = rotate_direction(current_dir, prim[:angle_offset])
        end

        num_pts = [2, (length * POINTS_PER_INCH).ceil].max
        straight_pts = build_straight(current_pt, current_dir, length, num_pts)

        # Track this segment (include the connection point from previous)
        @segments << { index: idx, type: :straight, points: straight_pts }

        @points += straight_pts[1..-1]  # Skip first (already added)
        current_pt = straight_pts.last.dup
        # Direction is now set by the straight (keeps the adjusted direction)
        @path_length += length

      when :turn
        radius = prim[:radius] || 5.0
        angle = prim[:angle] || 0
        direction = prim[:direction] || :right
        next if angle <= 0

        arc_length = radius * angle * Math::PI / 180
        num_pts = [2, (arc_length * POINTS_PER_INCH).ceil].max
        turn_pts = build_arc(current_pt, current_dir, radius, angle, direction, num_pts)

        # Track this segment
        @segments << { index: idx, type: :turn, points: turn_pts }

        @points += turn_pts[1..-1]  # Skip first (already added)
        current_pt = turn_pts.last.dup
        current_dir = tangent_at_arc_end(current_dir, angle, direction)
        @path_length += arc_length
      end
    end

    @points
  end

  # Calculate the closure gap (distance from end back to start)
  def closure_gap
    return 0.0 if @points.length < 2
    end_pt = @points.last
    Math.sqrt((end_pt[0] - @start_pt[0])**2 + (end_pt[1] - @start_pt[1])**2)
  end

  # Get the ending point and direction after building
  def end_point
    @points.last&.dup
  end

  def end_direction
    return @start_dir.dup if @points.length < 2

    # Calculate direction from last two points
    p1 = @points[-2]
    p2 = @points[-1]
    dir = [p2[0] - p1[0], p2[1] - p1[1]]
    normalize(dir)
  end

  private

  def normalize(vec)
    len = Math.sqrt(vec[0]**2 + vec[1]**2)
    return [1.0, 0.0] if len < 0.0001
    [vec[0] / len, vec[1] / len]
  end

  # Rotate a direction vector by angle_degrees (positive = clockwise in SVG coords)
  def rotate_direction(dir, angle_degrees)
    angle_rad = angle_degrees * Math::PI / 180.0
    cos_a = Math.cos(angle_rad)
    sin_a = Math.sin(angle_rad)
    [
      dir[0] * cos_a - dir[1] * sin_a,
      dir[0] * sin_a + dir[1] * cos_a
    ]
  end

  # Build a straight run from a point in a direction
  def build_straight(start_pt, direction, distance, num_points)
    points = []
    num_points.times do |i|
      t = i.to_f / (num_points - 1)
      d = t * distance
      points << [start_pt[0] + direction[0] * d, start_pt[1] + direction[1] * d]
    end
    points
  end

  # Build an arc starting at a point with given tangent direction
  # Uses SVG coordinate system (Y increases downward)
  def build_arc(start_pt, tangent_dir, radius, angle_degrees, direction, num_points)
    angle_rad = angle_degrees * Math::PI / 180.0

    # Perpendicular to tangent (points toward arc center)
    # In SVG coordinates (Y down):
    # :left turn = counter-clockwise visually = center is to the left
    # :right turn = clockwise visually = center is to the right
    perp = if direction == :left
      [tangent_dir[1], -tangent_dir[0]]  # 90 degrees CCW
    else
      [-tangent_dir[1], tangent_dir[0]]  # 90 degrees CW
    end

    # Arc center
    cx = start_pt[0] + perp[0] * radius
    cy = start_pt[1] + perp[1] * radius

    # Starting angle (from center to start point)
    start_angle = Math.atan2(start_pt[1] - cy, start_pt[0] - cx)

    # End angle depends on direction
    # In SVG coords: left = CCW visual = decreasing angle
    #               right = CW visual = increasing angle
    end_angle = if direction == :left
      start_angle - angle_rad
    else
      start_angle + angle_rad
    end

    # Generate arc points
    points = []
    num_points.times do |i|
      t = i.to_f / (num_points - 1)
      angle = start_angle + t * (end_angle - start_angle)
      points << [cx + radius * Math.cos(angle), cy + radius * Math.sin(angle)]
    end
    points
  end

  # Calculate tangent direction at end of an arc
  def tangent_at_arc_end(initial_tangent, angle_degrees, direction)
    angle_rad = angle_degrees * Math::PI / 180.0
    # In SVG coords: left turn rotates tangent CCW (negative angle)
    #               right turn rotates tangent CW (positive angle)
    angle_rad = -angle_rad if direction == :left

    cos_a = Math.cos(angle_rad)
    sin_a = Math.sin(angle_rad)

    [
      initial_tangent[0] * cos_a - initial_tangent[1] * sin_a,
      initial_tangent[0] * sin_a + initial_tangent[1] * cos_a
    ]
  end
end
