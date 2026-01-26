#!/usr/bin/env ruby

# Silverstone F1 Track Piece Generator
# Generates SVG pieces for CNC cutting from walnut wood
# Optimized for Hot Wheels Premium F1 cars

#===============================================================================
# CONFIGURATION
#===============================================================================

# Input/Output files
INPUT_FILE = 'silverstone.svg'
OUTPUT_FILE = 'silverstone-split.svg'

# Hot Wheels Premium F1 car dimensions (inches)
PREMIUM_CAR_LENGTH_IN = 3.47
PREMIUM_CAR_WIDTH_IN = 1.2225
PREMIUM_CAR_HEIGHT_IN = 0.69

# Hot Wheels mainline car dimensions (inches)
MAINLINE_CAR_LENGTH_IN = 3.159
MAINLINE_CAR_WIDTH_IN = 1.188
MAINLINE_CAR_HEIGHT_IN = 0.708

# LEGO car dimensions (inches)
LEGO_CAR_LENGTH_IN = 2.959
LEGO_CAR_WIDTH_IN = 1.254
LEGO_CAR_HEIGHT_IN = 0.996

# Test car visualization - shows car rectangles on the track
# Uses normalized coordinates: t=0.0 is at split 1 (start/finish), increases around the lap
# The actual track t-values are offset by START_FINISH_T internally
TEST_CARS = [
  { type: :premium, t: 0.02 },
  { type: :mainline, t: 0.05 },
  { type: :lego, t: 0.08 },
]
TEST_CAR_COLORS = {
  premium:  '#00AA00',  # Green
  mainline: '#0066CC',  # Blue
  lego:     '#FF8800',  # Orange
}
TEST_CAR_OPACITY = 0.7

# Track cross-section (U-shape profile, all in inches)
# The track is a U-shaped channel: two sidewalls with the car riding in between
INNER_TRACK_WIDTH_IN = 1.75   # Width of the channel where the car rides
SIDEWALL_THICKNESS_IN = 0.25  # Thickness of each side wall
SIDEWALL_HEIGHT_IN = 0.35     # Height of the side walls

# Total track width = inner channel + two sidewalls
TOTAL_TRACK_WIDTH_IN = INNER_TRACK_WIDTH_IN + (SIDEWALL_THICKNESS_IN * 2)

# Turning constraints (in inches)
# Minimum radius should be at least 1.5x car length for smooth turns
MIN_TURN_RADIUS_IN = 4.5
COMFORTABLE_TURN_RADIUS_IN = 5.5

# Maximum assembled track size (in inches)
MAX_TRACK_DIMENSION_IN = 60.0     # 5 feet

# Wood/CNC constraints (in inches)
MAX_PIECE_LENGTH_IN = 11.12       # Max length of a single piece (for wood grain)
MIN_PIECE_LENGTH_IN = 3.4        # Min length to be practical
WOOD_THICKNESS_IN = 0.75          # 3/4 inch walnut

#===============================================================================
# SCALING CONFIGURATION
#===============================================================================
# Choose a scaling mode to fit the track within TARGET_MAX_DIMENSION_IN
#
# TRADE-OFFS:
# - Smaller track = tighter curves (physics constraint)
# - To fit Silverstone in 60" with 4.5" min turn radius is geometrically
#   impossible without simplifying the chicanes in the source SVG.
#
# Scaling mode options:
#   :none    - No scaling (original ~156" x 118")
#   :uniform - Scale everything equally (RECOMMENDED)
#              Hits exact target, but curves get tighter
SCALING_MODE = :uniform

# Target maximum dimension (width or height) in inches
TARGET_MAX_DIMENSION_IN = MAX_TRACK_DIMENSION_IN

# Straight piece simplification
STRAIGHTEN_THRESHOLD = 0.015      # Max average curvature to simplify to a straight line

# Piece geometry overrides
# For pieces that need custom geometry (like smoothing a tight chicane), specify the
# piece number and the override method to call. The method receives start/end points
# and returns an array of points for the new path.
PIECE_OVERRIDES = {
  3 => :generate_piece_3_override,  # Replace tight chicane with wider sweeping curves
}



#===============================================================================
# MANUAL SPLIT CONFIGURATION
#===============================================================================
# Define ALL splits manually as t-values (0.0 to 1.0 along the track path).
# Split 1 is always at t=0 (start/finish line), so don't include it here.
# List remaining splits in racing order.

# Track coordinate system offset - this is the raw t-value of split 1 (start/finish)
# All user-facing t-values are normalized so t=0.0 is at split 1
START_FINISH_T = 0.515

# All splits in normalized coordinates (t=0.0 is split 1, increases in racing direction)
# Split 1 is automatically at t=0.0
MANUAL_SPLITS = [
  0.04,   # Split 2
  0.115,  # Split 3
  0.261,  # Split 4
  0.285,  # Split 5
  0.457,  # Split 6
  0.56,  # Split 7
  0.60,  # Split 8
  0.745,  # Split 9
  0.82,  # Split 10
  0.89,   # Split 11
]


# Visual settings for split preview (all dimensions in inches)
SPLIT_LINE_COLOR = '#FF0000'
SPLIT_LINE_WIDTH_IN = 0.05         # Thin line for precise split visualization
SVG_PADDING_IN = 5.0              # White border padding around the SVG (inches)

# Display scale - multiplier for SVG width/height attributes
# ViewBox stays in inches (for CNC), but display size is scaled up for viewing
# 10 = 10 pixels per inch when viewed in browser
SVG_DISPLAY_SCALE = 8

# Ghost track settings - shows original track for comparison
SHOW_GHOST_TRACK = true           # Enable ghost track overlay
GHOST_TRACK_COLOR = '#FF0000'     # Red for ghost (original track)
GHOST_TRACK_WIDTH_IN = 0.3        # Line thickness (inches)
GHOST_TRACK_OPACITY = 0.3         # Transparency (0-1)
GHOST_TRACK_STYLE = 'solid'       # 'solid' or 'dashed'

# Edit path settings - shows the editable centerline for curve editing
SHOW_EDIT_PATH = true             # Enable blue edit path overlay
EDIT_PATH_COLOR = '#0066FF'       # Blue for edit path
EDIT_PATH_WIDTH_IN = 0.5         # Thicker line for visibility
EDIT_PATH_OPACITY = 0.3          # Full opacity for editing

# Rendering toggles - disable to focus on path editing
SHOW_SIDEWALLS = false            # Render the U-shaped track profile
SHOW_TEST_CARS = false            # Render test car visualizations
SHOW_WOOD_GRAIN = false           # Render grain direction lines

# Tight radius warning visualization
SHOW_TIGHT_RADIUS_WARNINGS = false # Highlight curves that are too tight for cars
TIGHT_RADIUS_THRESHOLD_IN = 2   # Warn about radii below this (inches)
TIGHT_RADIUS_COLOR = '#FF00FF'    # Magenta for warnings

# Main track visual style - U-shaped profile representation
# NOTE: All dimensions below are in INCHES (output SVG uses 1 unit = 1 inch for CNC)
# The track is rendered as two rails (sidewalls) with a gap (inner channel) between them
TRACK_OUTER_WIDTH_IN = TOTAL_TRACK_WIDTH_IN  # Total width including sidewalls
TRACK_RAIL_WIDTH_IN = SIDEWALL_THICKNESS_IN  # Each rail represents a sidewall
TRACK_COLOR = '#000000'                      # Color of the sidewalls

# Grain direction visualization
SHOW_GRAIN_DIRECTION = true       # Show optimal grain direction for each piece
GRAIN_LINE_COLOR = '#5D3A1A'      # Dark brown for wood grain
GRAIN_LINE_OPACITY = 0.3          # Subtle grain lines
GRAIN_LINE_SPACING_IN = 0.4       # Spacing between grain lines (inches)
GRAIN_LINE_WIDTH_IN = 0.05        # Width of grain lines (inches)

# Scale bar settings
SHOW_SCALE_BAR = true             # Show scale reference in lower left
SCALE_BAR_COLOR = '#000000'       # Color of scale bar
SCALE_BAR_HEIGHT_IN = 0.5         # Height of the scale bar (inches)

# Background grid settings
SHOW_BACKGROUND_GRID = true       # Show subtle 1" grid in background
GRID_SIZE_IN = 1.0                # Grid cell size in inches
GRID_COLOR = '#CCCCCC'            # Light gray for subtle grid
GRID_LINE_WIDTH_IN = 0.02         # Thin grid lines (inches)

#===============================================================================
# SVG PATH PARSER
#===============================================================================

class PathParser
  attr_reader :commands

  def initialize(path_data)
    @path_data = path_data
    @commands = []
    parse
  end

  private

  def parse
    # Tokenize the path data - handle compact SVG number notation
    # Numbers can be separated by spaces, commas, or just by the start of a new number (-)
    # Also handles scientific notation like 1.5e-10
    tokens = []

    @path_data.scan(/([MmLlHhVvCcSsQqTtAaZz])|(-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)/i) do |cmd, num|
      if cmd
        tokens << cmd
      elsif num
        tokens << num.to_f
      end
    end

    current_command = nil
    current_args = []

    tokens.each do |token|
      if token.is_a?(String) && token =~ /[MmLlHhVvCcSsQqTtAaZz]/
        # Save previous command if exists
        if current_command
          @commands << { type: current_command, args: current_args }
        end
        current_command = token
        current_args = []
      else
        current_args << token.to_f
      end
    end

    # Save last command
    if current_command
      @commands << { type: current_command, args: current_args }
    end
  end
end

#===============================================================================
# BEZIER CURVE UTILITIES
#===============================================================================

#===============================================================================
# PIECE OVERRIDE GENERATORS
#===============================================================================

class PieceOverrideGenerator
  # Generate a circular arc from start_pt to end_pt with given radius
  # direction: :left or :right (which way the arc curves)
  # Returns array of points along the arc
  def self.generate_arc(start_pt, end_pt, radius, direction, num_points = 50)
    # Vector from start to end
    dx = end_pt[0] - start_pt[0]
    dy = end_pt[1] - start_pt[1]
    chord_len = Math.sqrt(dx**2 + dy**2)

    # If radius is too small for the chord, use minimum viable radius
    min_radius = chord_len / 2.0
    radius = [radius, min_radius + 0.1].max

    # Find the center of the arc
    # The center lies perpendicular to the chord midpoint
    mid_x = (start_pt[0] + end_pt[0]) / 2.0
    mid_y = (start_pt[1] + end_pt[1]) / 2.0

    # Distance from chord midpoint to arc center
    h = Math.sqrt(radius**2 - (chord_len/2.0)**2)

    # Perpendicular unit vector to chord
    perp_x = -dy / chord_len
    perp_y = dx / chord_len

    # Center position depends on direction
    if direction == :left
      cx = mid_x + perp_x * h
      cy = mid_y + perp_y * h
    else
      cx = mid_x - perp_x * h
      cy = mid_y - perp_y * h
    end

    # Angles from center to start and end
    start_angle = Math.atan2(start_pt[1] - cy, start_pt[0] - cx)
    end_angle = Math.atan2(end_pt[1] - cy, end_pt[0] - cx)

    # Ensure we go the right direction around the arc
    if direction == :left
      end_angle += 2 * Math::PI while end_angle < start_angle
    else
      end_angle -= 2 * Math::PI while end_angle > start_angle
    end

    # Generate points along the arc
    points = []
    num_points.times do |i|
      t = i.to_f / (num_points - 1)
      angle = start_angle + t * (end_angle - start_angle)
      x = cx + radius * Math.cos(angle)
      y = cy + radius * Math.sin(angle)
      points << [x, y]
    end

    points
  end

  # Generate a smooth S-curve (two connected arcs) from start to end
  # radius1, radius2: radii of the two arcs
  # split_ratio: where to split between arcs (0.0-1.0)
  def self.generate_s_curve(start_pt, end_pt, radius1, radius2, direction1, split_ratio = 0.5, num_points = 100)
    # Find an intermediate point for the two arcs to meet
    # This is approximate - we'll iterate to find a good connection point
    dx = end_pt[0] - start_pt[0]
    dy = end_pt[1] - start_pt[1]

    # Intermediate point along the direct line, offset perpendicular
    mid_t = split_ratio
    mid_base_x = start_pt[0] + dx * mid_t
    mid_base_y = start_pt[1] + dy * mid_t

    # The actual midpoint will be where the two arcs meet tangentially
    # For simplicity, use the base midpoint
    mid_pt = [mid_base_x, mid_base_y]

    direction2 = direction1 == :left ? :right : :left

    arc1 = generate_arc(start_pt, mid_pt, radius1, direction1, num_points / 2)
    arc2 = generate_arc(mid_pt, end_pt, radius2, direction2, num_points / 2)

    # Combine, removing duplicate midpoint
    arc1[0..-2] + arc2
  end

  # Store turn markers for visualization
  @turn_markers = []

  def self.turn_markers
    @turn_markers
  end

  def self.clear_turn_markers
    @turn_markers = []
  end

  # Piece 3 override: Build chicane from scratch, turn by turn
  # NOTE: original_points are in raw t-order, which is OPPOSITE to racing direction
  # Racing direction: piece 2 → piece 3 → piece 4
  # So we need to reverse: entry is from end_pt (piece 2 side), exit is to start_pt (piece 4 side)
  def self.generate_piece_3_override(original_points, start_pt, end_pt, entry_dir, exit_dir)
    # REVERSE for racing direction: entry is from piece 2 (end_pt), exit is to piece 4 (start_pt)
    racing_entry_pt = end_pt
    racing_exit_pt = start_pt
    racing_entry_dir = [-exit_dir[0], -exit_dir[1]]  # Reverse the exit direction
    racing_exit_dir = [-entry_dir[0], -entry_dir[1]]  # Reverse the entry direction

    # Normalize directions
    entry_len = Math.sqrt(racing_entry_dir[0]**2 + racing_entry_dir[1]**2)
    exit_len = Math.sqrt(racing_exit_dir[0]**2 + racing_exit_dir[1]**2)
    entry_unit = [racing_entry_dir[0] / entry_len, racing_entry_dir[1] / entry_len]
    exit_unit = [racing_exit_dir[0] / exit_len, racing_exit_dir[1] / exit_len]

    # Use racing direction start/end
    start_pt = racing_entry_pt
    end_pt = racing_exit_pt

    # === STRAIGHT RUNS (distance to travel before each turn) ===
    straight1 = 0.0       # inches before turn 1
    straight2 = 0.0       # inches before turn 2
    straight3 = 0.0       # inches before turn 3

    # === TURN 1 ===
    turn1_radius = 2.5        # inches
    turn1_angle = 110          # degrees
    turn1_direction = :right  # :left or :right (in racing direction)

    # === TURN 2 ===
    turn2_radius = 2.5        # inches
    turn2_angle = 140         # degrees
    turn2_direction = :left   # :left or :right (in racing direction)

    # === TURN 3 ===
    turn3_radius = 4        # inches
    turn3_angle = 60          # degrees
    turn3_direction = :left   # :left or :right (in racing direction)

    all_points = []
    @turn_markers = []  # Clear previous markers

    # Current position and direction
    current_pt = start_pt
    current_dir = entry_unit

    # Straight run before Turn 1
    if straight1 > 0
      straight1_points = build_straight_run(current_pt, current_dir, straight1, 10)
      all_points += straight1_points
      current_pt = straight1_points.last
    end

    # Record Turn 1 start position
    @turn_markers << { label: "T1", pt: current_pt.dup, dir: current_dir.dup }

    # Build Turn 1 (flip direction since entry is reversed)
    t1_actual = turn1_direction == :right ? :left : :right
    turn1_points = build_arc_from_tangent(
      current_pt, current_dir, turn1_radius, turn1_angle, t1_actual, 40
    )
    all_points += (all_points.empty? ? turn1_points : turn1_points[1..-1])
    current_pt = turn1_points.last
    current_dir = tangent_at_arc_end(current_dir, turn1_angle, t1_actual)

    # Straight run before Turn 2
    if straight2 > 0
      straight2_points = build_straight_run(current_pt, current_dir, straight2, 10)
      all_points += straight2_points[1..-1]
      current_pt = straight2_points.last
    end

    # Record Turn 2 start position
    @turn_markers << { label: "T2", pt: current_pt.dup, dir: current_dir.dup }

    # Build Turn 2 (flip direction since entry is reversed)
    t2_actual = turn2_direction == :right ? :left : :right
    turn2_points = build_arc_from_tangent(
      current_pt, current_dir, turn2_radius, turn2_angle, t2_actual, 50
    )
    all_points += turn2_points[1..-1]
    current_pt = turn2_points.last
    current_dir = tangent_at_arc_end(current_dir, turn2_angle, t2_actual)

    # Straight run before Turn 3
    if straight3 > 0
      straight3_points = build_straight_run(current_pt, current_dir, straight3, 10)
      all_points += straight3_points[1..-1]
      current_pt = straight3_points.last
    end

    # Record Turn 3 start position
    @turn_markers << { label: "T3", pt: current_pt.dup, dir: current_dir.dup }

    # Build Turn 3 (flip direction since entry is reversed)
    t3_actual = turn3_direction == :right ? :left : :right
    turn3_points = build_arc_from_tangent(
      current_pt, current_dir, turn3_radius, turn3_angle, t3_actual, 50
    )
    all_points += turn3_points[1..-1]
    current_pt = turn3_points.last
    current_dir = tangent_at_arc_end(current_dir, turn3_angle, t3_actual)

    # Smooth connector to end point
    connector_points = build_smooth_connector(
      current_pt, current_dir, end_pt, exit_unit, 30
    )

    # Add connector
    all_points += connector_points[1..-1]

    # IMPORTANT: Reverse the points to return in raw t-order (opposite of racing direction)
    all_points.reverse
  end

  # Build a straight run from a point in a direction
  def self.build_straight_run(start_pt, direction, distance, num_points)
    points = []
    num_points.times do |i|
      t = i.to_f / (num_points - 1)
      d = t * distance
      points << [start_pt[0] + direction[0] * d, start_pt[1] + direction[1] * d]
    end
    points
  end

  # Build an arc starting at a point with given tangent direction
  def self.build_arc_from_tangent(start_pt, tangent_dir, radius, angle_degrees, direction, num_points)
    angle_rad = angle_degrees * Math::PI / 180.0

    # Perpendicular to tangent (points toward arc center)
    perp = if direction == :right
      [tangent_dir[1], -tangent_dir[0]]  # 90° clockwise
    else
      [-tangent_dir[1], tangent_dir[0]]  # 90° counter-clockwise
    end

    # Arc center
    cx = start_pt[0] + perp[0] * radius
    cy = start_pt[1] + perp[1] * radius

    # Starting angle (from center to start point)
    start_angle = Math.atan2(start_pt[1] - cy, start_pt[0] - cx)

    # End angle depends on direction
    end_angle = if direction == :right
      start_angle - angle_rad  # Clockwise
    else
      start_angle + angle_rad  # Counter-clockwise
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
  def self.tangent_at_arc_end(initial_tangent, angle_degrees, direction)
    angle_rad = angle_degrees * Math::PI / 180.0
    angle_rad = -angle_rad if direction == :right

    cos_a = Math.cos(angle_rad)
    sin_a = Math.sin(angle_rad)

    [
      initial_tangent[0] * cos_a - initial_tangent[1] * sin_a,
      initial_tangent[0] * sin_a + initial_tangent[1] * cos_a
    ]
  end

  # Build a smooth bezier connector between two points with specified tangents
  def self.build_smooth_connector(start_pt, start_dir, end_pt, end_dir, num_points)
    dist = Math.sqrt((end_pt[0] - start_pt[0])**2 + (end_pt[1] - start_pt[1])**2)
    ctrl_dist = dist * 0.4

    p0 = start_pt
    p1 = [start_pt[0] + start_dir[0] * ctrl_dist, start_pt[1] + start_dir[1] * ctrl_dist]
    p2 = [end_pt[0] - end_dir[0] * ctrl_dist, end_pt[1] - end_dir[1] * ctrl_dist]
    p3 = end_pt

    points = []
    num_points.times do |i|
      t = i.to_f / (num_points - 1)
      points << BezierCurve.cubic_point(p0, p1, p2, p3, t)
    end
    points
  end

  # Generate a Catmull-Rom spline through control points
  # Unlike Bezier, this passes through ALL control points
  def self.catmull_rom_spline(control_points, total_points)
    return control_points if control_points.length < 4

    points = []
    n = control_points.length

    # Add phantom points at start and end for the spline
    # (extrapolate from first/last two points)
    p_start = [
      2 * control_points[0][0] - control_points[1][0],
      2 * control_points[0][1] - control_points[1][1]
    ]
    p_end = [
      2 * control_points[n-1][0] - control_points[n-2][0],
      2 * control_points[n-1][1] - control_points[n-2][1]
    ]

    extended = [p_start] + control_points + [p_end]

    # Points per segment
    segments = n - 1
    points_per_segment = (total_points.to_f / segments).ceil

    # Generate spline through each segment
    (0...segments).each do |seg|
      p0 = extended[seg]
      p1 = extended[seg + 1]
      p2 = extended[seg + 2]
      p3 = extended[seg + 3]

      num_pts = (seg == segments - 1) ? points_per_segment : points_per_segment - 1

      num_pts.times do |i|
        t = i.to_f / (points_per_segment - 1)
        pt = catmull_rom_point(p0, p1, p2, p3, t)
        points << pt
      end
    end

    # Ensure we end exactly at the last control point
    points[-1] = control_points.last

    points
  end

  # Evaluate Catmull-Rom spline at parameter t
  def self.catmull_rom_point(p0, p1, p2, p3, t)
    t2 = t * t
    t3 = t2 * t

    # Catmull-Rom basis matrix (tension = 0.5)
    x = 0.5 * (
      (2 * p1[0]) +
      (-p0[0] + p2[0]) * t +
      (2*p0[0] - 5*p1[0] + 4*p2[0] - p3[0]) * t2 +
      (-p0[0] + 3*p1[0] - 3*p2[0] + p3[0]) * t3
    )

    y = 0.5 * (
      (2 * p1[1]) +
      (-p0[1] + p2[1]) * t +
      (2*p0[1] - 5*p1[1] + 4*p2[1] - p3[1]) * t2 +
      (-p0[1] + 3*p1[1] - 3*p2[1] + p3[1]) * t3
    )

    [x, y]
  end

  # Find tight radius sections from piece_data points (the modified/edit path)
  # Returns array of { min_radius:, center_point: }
  def self.find_tight_sections_in_piece_data(piece_data, threshold_in)
    tight_sections = []

    piece_data.each do |pd|
      points = pd[:points]
      next if points.length < 3

      # Calculate curvature at each interior point
      (1...points.length - 1).each do |i|
        prev_pt = points[i - 1]
        pt = points[i]
        next_pt = points[i + 1]

        # Calculate curvature using the formula: |cross product| / |v1| * |v2| * |sum|
        v1 = [pt[0] - prev_pt[0], pt[1] - prev_pt[1]]
        v2 = [next_pt[0] - pt[0], next_pt[1] - pt[1]]

        cross = v1[0] * v2[1] - v1[1] * v2[0]
        len1 = Math.sqrt(v1[0]**2 + v1[1]**2)
        len2 = Math.sqrt(v2[0]**2 + v2[1]**2)

        next if len1 < 0.001 || len2 < 0.001

        # Menger curvature formula
        area = cross.abs / 2.0
        side_c = Math.sqrt((next_pt[0] - prev_pt[0])**2 + (next_pt[1] - prev_pt[1])**2)
        next if side_c < 0.001

        curvature = 4.0 * area / (len1 * len2 * side_c)
        next if curvature < 0.001

        radius = 1.0 / curvature

        if radius < threshold_in
          tight_sections << { min_radius: radius, center_point: pt, piece_num: pd[:piece_num] }
        end
      end
    end

    # Merge nearby points into single warnings (within 1 inch)
    return [] if tight_sections.empty?

    merged = []
    tight_sections.sort_by { |s| [s[:center_point][0], s[:center_point][1]] }.each do |section|
      # Check if close to an existing merged section
      found = merged.find do |m|
        dx = m[:center_point][0] - section[:center_point][0]
        dy = m[:center_point][1] - section[:center_point][1]
        Math.sqrt(dx**2 + dy**2) < 1.5
      end

      if found
        # Update if this is tighter
        if section[:min_radius] < found[:min_radius]
          found[:min_radius] = section[:min_radius]
          found[:center_point] = section[:center_point]
        end
      else
        merged << section.dup
      end
    end

    merged
  end
end

class BezierCurve
  # Evaluate cubic bezier at parameter t (0..1)
  def self.cubic_point(p0, p1, p2, p3, t)
    mt = 1 - t
    mt2 = mt * mt
    mt3 = mt2 * mt
    t2 = t * t
    t3 = t2 * t

    x = mt3 * p0[0] + 3 * mt2 * t * p1[0] + 3 * mt * t2 * p2[0] + t3 * p3[0]
    y = mt3 * p0[1] + 3 * mt2 * t * p1[1] + 3 * mt * t2 * p2[1] + t3 * p3[1]
    [x, y]
  end

  # Evaluate cubic bezier derivative at parameter t
  def self.cubic_derivative(p0, p1, p2, p3, t)
    mt = 1 - t
    mt2 = mt * mt
    t2 = t * t

    dx = 3 * mt2 * (p1[0] - p0[0]) + 6 * mt * t * (p2[0] - p1[0]) + 3 * t2 * (p3[0] - p2[0])
    dy = 3 * mt2 * (p1[1] - p0[1]) + 6 * mt * t * (p2[1] - p1[1]) + 3 * t2 * (p3[1] - p2[1])
    [dx, dy]
  end

  # Calculate curvature at parameter t
  def self.cubic_curvature(p0, p1, p2, p3, t)
    d1 = cubic_derivative(p0, p1, p2, p3, t)

    # Second derivative
    mt = 1 - t
    d2x = 6 * mt * (p2[0] - 2*p1[0] + p0[0]) + 6 * t * (p3[0] - 2*p2[0] + p1[0])
    d2y = 6 * mt * (p2[1] - 2*p1[1] + p0[1]) + 6 * t * (p3[1] - 2*p2[1] + p1[1])

    # Curvature = |x'y'' - y'x''| / (x'^2 + y'^2)^(3/2)
    numerator = (d1[0] * d2y - d1[1] * d2x).abs
    denominator = (d1[0]**2 + d1[1]**2) ** 1.5

    denominator > 0.0001 ? numerator / denominator : 0
  end
end

#===============================================================================
# TRACK SCALER
#===============================================================================

class TrackScaler
  attr_reader :scale_factor, :scaled_points, :scaled_curvatures, :scaled_tangents

  def initialize(points, curvatures, tangents)
    @original_points = points
    @original_curvatures = curvatures
    @original_tangents = tangents
    @scale_factor = 1.0
    @scaled_points = points.dup
    @scaled_curvatures = curvatures.dup
    @scaled_tangents = tangents.dup

    apply_scaling if SCALING_MODE != :none
  end

  def apply_scaling
    @scale_factor = calculate_base_scale_factor
    puts ""
    puts "="*60
    puts "SCALING: #{SCALING_MODE.to_s.upcase}"
    puts "="*60
    report_original_dimensions

    case SCALING_MODE
    when :uniform
      apply_uniform_scale
    end

    report_scaled_dimensions
  end

  private

  def calculate_base_scale_factor
    # Scale so output coordinates are directly in inches (1 SVG unit = 1 inch)
    # This makes CNC import straightforward
    bounds = calculate_bounds(@original_points)
    max_dim_svg = [bounds[:width], bounds[:height]].max
    # scale_factor converts original SVG units to inches
    TARGET_MAX_DIMENSION_IN / max_dim_svg
  end

  def calculate_bounds(points)
    all_x = points.map { |p| p[0] }
    all_y = points.map { |p| p[1] }
    {
      width: all_x.max - all_x.min,
      height: all_y.max - all_y.min,
      min_x: all_x.min,
      max_x: all_x.max,
      min_y: all_y.min,
      max_y: all_y.max,
      center_x: (all_x.min + all_x.max) / 2.0,
      center_y: (all_y.min + all_y.max) / 2.0
    }
  end

  def report_original_dimensions
    bounds = calculate_bounds(@original_points)
    # Original dimensions are in arbitrary SVG units - estimate based on scale factor
    # After scaling, we'll have the target dimensions
    puts "Original SVG bounds: #{bounds[:width].round(1)} x #{bounds[:height].round(1)} units"
  end

  def report_scaled_dimensions
    bounds = calculate_bounds(@scaled_points)
    # After scaling, coordinates ARE in inches (1 unit = 1 inch)
    width_in = bounds[:width]
    height_in = bounds[:height]
    puts "Output:   #{width_in.round(1)}\" x #{height_in.round(1)}\" (#{format_feet_inches(width_in)} x #{format_feet_inches(height_in)})"
    puts "Scale factor: #{@scale_factor.round(6)}"
    puts "Output units: 1 SVG unit = 1 inch (CNC-ready)"

    # Check for radius violations
    check_radius_violations
  end

  def format_feet_inches(inches)
    feet = (inches / 12).floor
    remaining = (inches % 12).round(1)
    feet > 0 ? "#{feet}' #{remaining}\"" : "#{remaining}\""
  end

  def check_radius_violations
    violations = 0
    min_radius_found = Float::INFINITY

    @scaled_curvatures.each do |curv|
      next if curv < 0.0001  # Skip near-zero curvature (straight sections)
      # After scaling, radius is directly in inches (1/curvature)
      radius_in = 1.0 / curv
      min_radius_found = [min_radius_found, radius_in].min
      violations += 1 if radius_in < MIN_TURN_RADIUS_IN
    end

    if violations > 0
      puts "WARNING: #{violations} points have turn radius < #{MIN_TURN_RADIUS_IN}\" minimum"
      puts "         Minimum radius found: #{min_radius_found.round(2)}\""
    else
      puts "All turn radii OK (minimum: #{min_radius_found.round(2)}\")"
    end
  end

  #=============================================================================
  # UNIFORM SCALING
  #=============================================================================

  def apply_uniform_scale
    bounds = calculate_bounds(@original_points)
    center_x = bounds[:center_x]
    center_y = bounds[:center_y]

    @scaled_points = @original_points.map do |pt|
      [
        center_x + (pt[0] - center_x) * @scale_factor,
        center_y + (pt[1] - center_y) * @scale_factor
      ]
    end

    # Curvature scales inversely with size (smaller track = tighter curves)
    @scaled_curvatures = @original_curvatures.map { |c| c / @scale_factor }

    # Tangent directions don't change with uniform scaling
    @scaled_tangents = @original_tangents.dup
  end

  def recalculate_curvatures
    # Recalculate curvatures from the modified points
    @scaled_curvatures = []
    @scaled_tangents = []

    @scaled_points.each_with_index do |pt, i|
      if i == 0
        # First point: use forward difference
        next_pt = @scaled_points[1]
        dx = next_pt[0] - pt[0]
        dy = next_pt[1] - pt[1]
        len = Math.sqrt(dx * dx + dy * dy)
        @scaled_tangents << (len > 0 ? [dx / len, dy / len] : [1, 0])
        @scaled_curvatures << 0
      elsif i == @scaled_points.length - 1
        # Last point: use backward difference
        prev_pt = @scaled_points[i - 1]
        dx = pt[0] - prev_pt[0]
        dy = pt[1] - prev_pt[1]
        len = Math.sqrt(dx * dx + dy * dy)
        @scaled_tangents << (len > 0 ? [dx / len, dy / len] : [1, 0])
        @scaled_curvatures << 0
      else
        # Interior point: use central difference for tangent
        prev_pt = @scaled_points[i - 1]
        next_pt = @scaled_points[i + 1]

        dx = next_pt[0] - prev_pt[0]
        dy = next_pt[1] - prev_pt[1]
        len = Math.sqrt(dx * dx + dy * dy)
        tangent = len > 0 ? [dx / len, dy / len] : [1, 0]
        @scaled_tangents << tangent

        # Curvature from discrete points
        # Using the formula: k = 2 * |cross(v1, v2)| / (|v1| * |v2| * |v1 + v2|)
        v1 = [pt[0] - prev_pt[0], pt[1] - prev_pt[1]]
        v2 = [next_pt[0] - pt[0], next_pt[1] - pt[1]]

        cross = v1[0] * v2[1] - v1[1] * v2[0]
        len1 = Math.sqrt(v1[0]**2 + v1[1]**2)
        len2 = Math.sqrt(v2[0]**2 + v2[1]**2)
        sum_len = Math.sqrt((v1[0] + v2[0])**2 + (v1[1] + v2[1])**2)

        denom = len1 * len2 * sum_len
        curv = denom > 0.0001 ? (2 * cross.abs / denom) : 0
        @scaled_curvatures << curv
      end
    end
  end
end

#===============================================================================
# TRACK ANALYZER
#===============================================================================

class TrackAnalyzer
  attr_reader :points, :curvatures, :path_length, :scale_factor

  def initialize(path_data, samples_per_curve: 50)
    @path_data = path_data
    @samples_per_curve = samples_per_curve
    @points = []
    @curvatures = []
    @tangents = []
    @scale_factor = 1.0
    analyze
    apply_scaling
  end

  def apply_scaling
    return if SCALING_MODE == :none

    scaler = TrackScaler.new(@points, @curvatures, @tangents)
    @points = scaler.scaled_points
    @curvatures = scaler.scaled_curvatures
    @tangents = scaler.scaled_tangents
    @scale_factor = scaler.scale_factor

    # Recalculate path length with scaled points
    @path_length = 0.0
    (1...@points.length).each do |i|
      dx = @points[i][0] - @points[i-1][0]
      dy = @points[i][1] - @points[i-1][1]
      @path_length += Math.sqrt(dx*dx + dy*dy)
    end
  end

  def point_at(t)
    index = (t * (@points.length - 1)).round
    index = [[index, 0].max, @points.length - 1].min
    @points[index]
  end

  def tangent_at(t)
    index = (t * (@tangents.length - 1)).round
    index = [[index, 0].max, @tangents.length - 1].min
    @tangents[index]
  end

  # Calculate optimal grain direction for a piece between t_start and t_end
  # Returns a normalized vector representing the grain direction
  def optimal_grain_direction(t_start, t_end)
    start_idx = (t_start * (@tangents.length - 1)).round
    end_idx = (t_end * (@tangents.length - 1)).round

    start_idx = [[start_idx, 0].max, @tangents.length - 1].min
    end_idx = [[end_idx, 0].max, @tangents.length - 1].min

    return @tangents[start_idx] if end_idx <= start_idx

    # Method: Use principal component analysis approach
    # Sum all tangent vectors (but handle direction flipping)
    # The grain should align with the predominant direction of the piece

    # First, get all tangents in this segment
    segment_tangents = @tangents[start_idx..end_idx]

    # Use the first tangent as reference direction
    ref = segment_tangents.first

    # Sum tangents, flipping any that point opposite to reference
    sum_x = 0.0
    sum_y = 0.0

    segment_tangents.each do |t|
      dot = t[0] * ref[0] + t[1] * ref[1]
      if dot >= 0
        sum_x += t[0]
        sum_y += t[1]
      else
        sum_x -= t[0]
        sum_y -= t[1]
      end
    end

    # Normalize
    len = Math.sqrt(sum_x * sum_x + sum_y * sum_y)
    return ref if len < 0.001

    [sum_x / len, sum_y / len]
  end

  # Get bounding box for a piece between t_start and t_end
  def piece_bounds(t_start, t_end)
    start_idx = (t_start * (@points.length - 1)).round
    end_idx = (t_end * (@points.length - 1)).round

    start_idx = [[start_idx, 0].max, @points.length - 1].min
    end_idx = [[end_idx, 0].max, @points.length - 1].min

    return nil if end_idx <= start_idx

    segment_points = @points[start_idx..end_idx]

    min_x = segment_points.map { |p| p[0] }.min
    max_x = segment_points.map { |p| p[0] }.max
    min_y = segment_points.map { |p| p[1] }.min
    max_y = segment_points.map { |p| p[1] }.max

    { min_x: min_x, max_x: max_x, min_y: min_y, max_y: max_y }
  end

  # Get all points for a piece (for clipping grain lines)
  def piece_points(t_start, t_end)
    start_idx = (t_start * (@points.length - 1)).round
    end_idx = (t_end * (@points.length - 1)).round

    start_idx = [[start_idx, 0].max, @points.length - 1].min
    end_idx = [[end_idx, 0].max, @points.length - 1].min

    @points[start_idx..end_idx]
  end

  # Find sections where the turn radius is below a threshold
  def find_tight_radius_sections(threshold_in)
    tight_sections = []
    in_tight = false
    section_start_idx = 0
    max_curv_in_section = 0

    @curvatures.each_with_index do |curv, i|
      next if curv < 0.0001
      radius_in = 1.0 / curv

      if radius_in < threshold_in
        if !in_tight
          in_tight = true
          section_start_idx = i
          max_curv_in_section = curv
        else
          max_curv_in_section = [max_curv_in_section, curv].max
        end
      elsif in_tight
        t_start = section_start_idx.to_f / @points.length
        t_end = i.to_f / @points.length
        center_idx = ((t_start + t_end) / 2.0 * (@points.length - 1)).round
        tight_sections << {
          t_start: t_start, t_end: t_end,
          min_radius: 1.0 / max_curv_in_section,
          center_point: @points[center_idx]
        }
        in_tight = false
        max_curv_in_section = 0
      end
    end

    # Merge nearby sections
    return tight_sections if tight_sections.length < 2
    merged = [tight_sections.first.dup]
    tight_sections[1..-1].each do |section|
      if section[:t_start] - merged.last[:t_end] < 0.02
        merged.last[:t_end] = section[:t_end]
        merged.last[:min_radius] = [merged.last[:min_radius], section[:min_radius]].min
        center_idx = ((merged.last[:t_start] + merged.last[:t_end]) / 2.0 * (@points.length - 1)).round
        merged.last[:center_point] = @points[center_idx]
      else
        merged << section.dup
      end
    end
    merged
  end

  # Check if a piece is "straight enough" to be simplified to a line
  def is_piece_straight?(t_start, t_end)
    start_idx = (t_start * (@curvatures.length - 1)).round
    end_idx = (t_end * (@curvatures.length - 1)).round

    start_idx = [[start_idx, 0].max, @curvatures.length - 1].min
    end_idx = [[end_idx, 0].max, @curvatures.length - 1].min

    return false if end_idx <= start_idx

    segment_curvatures = @curvatures[start_idx..end_idx]
    avg_curvature = segment_curvatures.sum / segment_curvatures.length.to_f
    max_curvature = segment_curvatures.max

    # A piece is straight if its average curvature is below threshold
    # and no point has extremely high curvature
    avg_curvature < STRAIGHTEN_THRESHOLD && max_curvature < STRAIGHTEN_THRESHOLD * 3
  end

  private

  def analyze
    parser = PathParser.new(@path_data)

    current_x = 0.0
    current_y = 0.0

    parser.commands.each do |cmd|
      case cmd[:type]
      when 'M', 'm'
        # Move to
        args = cmd[:args]
        if cmd[:type] == 'M'
          current_x = args[0]
          current_y = args[1]
        else
          current_x += args[0]
          current_y += args[1]
        end
        @points << [current_x, current_y]
        @curvatures << 0
        @tangents << [1, 0]  # Default tangent

      when 'c'
        # Relative cubic bezier - may have multiple sets of coordinates
        args = cmd[:args]
        i = 0
        while i < args.length
          p0 = [current_x, current_y]
          p1 = [current_x + args[i], current_y + args[i+1]]
          p2 = [current_x + args[i+2], current_y + args[i+3]]
          p3 = [current_x + args[i+4], current_y + args[i+5]]

          # Sample this curve
          (1..@samples_per_curve).each do |s|
            t = s.to_f / @samples_per_curve
            pt = BezierCurve.cubic_point(p0, p1, p2, p3, t)
            curv = BezierCurve.cubic_curvature(p0, p1, p2, p3, t)
            deriv = BezierCurve.cubic_derivative(p0, p1, p2, p3, t)

            # Normalize tangent
            len = Math.sqrt(deriv[0]**2 + deriv[1]**2)
            tangent = len > 0 ? [deriv[0]/len, deriv[1]/len] : [1, 0]

            @points << pt
            @curvatures << curv
            @tangents << tangent
          end

          current_x = p3[0]
          current_y = p3[1]
          i += 6
        end

      when 'C'
        # Absolute cubic bezier
        args = cmd[:args]
        i = 0
        while i < args.length
          p0 = [current_x, current_y]
          p1 = [args[i], args[i+1]]
          p2 = [args[i+2], args[i+3]]
          p3 = [args[i+4], args[i+5]]

          (1..@samples_per_curve).each do |s|
            t = s.to_f / @samples_per_curve
            pt = BezierCurve.cubic_point(p0, p1, p2, p3, t)
            curv = BezierCurve.cubic_curvature(p0, p1, p2, p3, t)
            deriv = BezierCurve.cubic_derivative(p0, p1, p2, p3, t)

            len = Math.sqrt(deriv[0]**2 + deriv[1]**2)
            tangent = len > 0 ? [deriv[0]/len, deriv[1]/len] : [1, 0]

            @points << pt
            @curvatures << curv
            @tangents << tangent
          end

          current_x = p3[0]
          current_y = p3[1]
          i += 6
        end

      when 'z', 'Z'
        # Close path - handled implicitly
      end
    end

    # Calculate approximate path length
    @path_length = 0.0
    (1...@points.length).each do |i|
      dx = @points[i][0] - @points[i-1][0]
      dy = @points[i][1] - @points[i-1][1]
      @path_length += Math.sqrt(dx*dx + dy*dy)
    end

    # Fix the first tangent (from 'M' command) using the tangent from nearby points
    if @tangents.length > 1
      @tangents[0] = @tangents[1]
    end
  end
end

#===============================================================================
# SVG GENERATOR
#===============================================================================

class SplitVisualizer
  def initialize(input_file, output_file)
    @input_file = input_file
    @output_file = output_file
  end

  # Generate grain lines for a single piece, clipped to the track width
  def generate_grain_lines_for_piece(grain_dir, bounds, piece_pts, path_data, t_start, t_end)
    return "" if piece_pts.length < 2

    lines = []

    # Calculate perpendicular to grain direction
    perp = [-grain_dir[1], grain_dir[0]]

    # Calculate the extent of the bounding box along the perpendicular direction
    # to determine how many grain lines we need
    center_x = (bounds[:min_x] + bounds[:max_x]) / 2.0
    center_y = (bounds[:min_y] + bounds[:max_y]) / 2.0

    # Find extent of bounding box
    diagonal = Math.sqrt((bounds[:max_x] - bounds[:min_x])**2 + (bounds[:max_y] - bounds[:min_y])**2)

    # Number of lines needed to cover the piece
    num_lines = (diagonal / GRAIN_LINE_SPACING_IN).ceil + 2

    # Generate parallel lines along the grain direction
    (-num_lines..num_lines).each do |i|
      # Offset from center along perpendicular direction
      offset = i * GRAIN_LINE_SPACING_IN

      # Line passes through this point and extends in grain direction
      base_x = center_x + perp[0] * offset
      base_y = center_y + perp[1] * offset

      # Extend line far enough to cross the bounding box
      x1 = base_x - grain_dir[0] * diagonal
      y1 = base_y - grain_dir[1] * diagonal
      x2 = base_x + grain_dir[0] * diagonal
      y2 = base_y + grain_dir[1] * diagonal

      # Clip this line to the track shape (simplified: just add it, will use SVG clipping)
      lines << [x1, y1, x2, y2]
    end

    # Generate SVG for these grain lines with a clip path based on the piece shape
    # Create a polygon from the piece points (track centerline expanded to total track width)
    clip_path_id = "grain-clip-#{(t_start * 1000).round}-#{(t_end * 1000).round}"

    # Build clip path from piece points expanded to total track width (inner + sidewalls)
    half_width = TOTAL_TRACK_WIDTH_IN / 2.0

    # Create outline by offsetting piece points in both perpendicular directions
    outline_points = []

    # Forward pass (one side)
    piece_pts.each_with_index do |pt, idx|
      # Get tangent at this point (approximate from neighbors)
      if idx == 0
        next_pt = piece_pts[1]
        dx = next_pt[0] - pt[0]
        dy = next_pt[1] - pt[1]
      elsif idx == piece_pts.length - 1
        prev_pt = piece_pts[idx - 1]
        dx = pt[0] - prev_pt[0]
        dy = pt[1] - prev_pt[1]
      else
        prev_pt = piece_pts[idx - 1]
        next_pt = piece_pts[[idx + 1, piece_pts.length - 1].min]
        dx = next_pt[0] - prev_pt[0]
        dy = next_pt[1] - prev_pt[1]
      end

      len = Math.sqrt(dx * dx + dy * dy)
      next if len < 0.001

      # Perpendicular
      perp_x = -dy / len
      perp_y = dx / len

      outline_points << [pt[0] + perp_x * half_width, pt[1] + perp_y * half_width]
    end

    # Reverse pass (other side)
    piece_pts.reverse.each_with_index do |pt, idx|
      actual_idx = piece_pts.length - 1 - idx
      if actual_idx == 0
        next_pt = piece_pts[1]
        dx = next_pt[0] - pt[0]
        dy = next_pt[1] - pt[1]
      elsif actual_idx == piece_pts.length - 1
        prev_pt = piece_pts[actual_idx - 1]
        dx = pt[0] - prev_pt[0]
        dy = pt[1] - prev_pt[1]
      else
        prev_pt = piece_pts[actual_idx - 1]
        next_pt = piece_pts[[actual_idx + 1, piece_pts.length - 1].min]
        dx = next_pt[0] - prev_pt[0]
        dy = next_pt[1] - prev_pt[1]
      end

      len = Math.sqrt(dx * dx + dy * dy)
      next if len < 0.001

      perp_x = -dy / len
      perp_y = dx / len

      outline_points << [pt[0] - perp_x * half_width, pt[1] - perp_y * half_width]
    end

    return "" if outline_points.length < 4

    # Build the SVG clip path and lines
    polygon_pts = outline_points.map { |p| "#{p[0].round(2)},#{p[1].round(2)}" }.join(" ")

    svg = %(<clipPath id="#{clip_path_id}">\n)
    svg += %(<polygon points="#{polygon_pts}"/>\n)
    svg += %(</clipPath>\n)

    svg += %(<g clip-path="url(##{clip_path_id})" opacity="#{GRAIN_LINE_OPACITY}">\n)
    lines.each do |line|
      svg += %(<line x1="#{line[0].round(2)}" y1="#{line[1].round(2)}" x2="#{line[2].round(2)}" y2="#{line[3].round(2)}" stroke="#{GRAIN_LINE_COLOR}" stroke-width="#{GRAIN_LINE_WIDTH_IN}"/>\n)
    end
    svg += %(</g>\n)

    svg
  end

  # Build a modified path that straightens "straight enough" pieces
  # Returns: { path: String, piece_data: Array of {piece_num, t_start, t_end, points} }
  def build_modified_path(analyzer, splits, original_path_data, splits_normalized)
    # Get all t-values where we need to check for straightening
    # These are the boundaries between pieces
    all_t_values = splits.dup.sort

    # Ensure we have 0.0 and 1.0
    all_t_values.unshift(0.0) unless all_t_values.first == 0.0
    all_t_values.push(1.0) unless all_t_values.last == 1.0
    all_t_values = all_t_values.sort.uniq

    # Build a mapping from raw t ranges to piece numbers
    piece_t_ranges = build_piece_t_ranges(splits, splits_normalized)

    # Build the path by going through each segment
    path_commands = []
    first_point = analyzer.point_at(0.0)
    path_commands << "M #{first_point[0].round(3)} #{first_point[1].round(3)}"

    straightened_pieces = []
    piece_data = []  # Store piece info for per-piece rendering

    (0...all_t_values.length - 1).each do |i|
      t_start = all_t_values[i]
      t_end = all_t_values[i + 1]

      # Find which piece number this segment belongs to
      piece_num = find_piece_number(t_start, t_end, piece_t_ranges)

      is_straight = analyzer.is_piece_straight?(t_start, t_end)

      if is_straight
        # Just draw a straight line to the end point
        end_point = analyzer.point_at(t_end)
        path_commands << "L #{end_point[0].round(3)} #{end_point[1].round(3)}"
        straightened_pieces << [t_start, t_end, piece_num]
        piece_data << { piece_num: piece_num, t_start: t_start, t_end: t_end, points: [analyzer.point_at(t_start), end_point] }
      elsif PIECE_OVERRIDES.key?(piece_num)
        # Apply custom geometry override for this piece
        original_pts = analyzer.piece_points(t_start, t_end)
        start_pt = original_pts.first
        end_pt = original_pts.last

        # Calculate entry and exit directions from original path
        entry_dir = [original_pts[1][0] - original_pts[0][0], original_pts[1][1] - original_pts[0][1]]
        exit_dir = [original_pts[-1][0] - original_pts[-2][0], original_pts[-1][1] - original_pts[-2][1]]

        # Call the override generator
        override_method = PIECE_OVERRIDES[piece_num]
        piece_pts = PieceOverrideGenerator.send(override_method, original_pts, start_pt, end_pt, entry_dir, exit_dir)

        @overridden_pieces ||= []
        @overridden_pieces << [piece_num, original_pts.length, piece_pts.length]

        piece_data << { piece_num: piece_num, t_start: t_start, t_end: t_end, points: piece_pts }

        # Skip the first point (it's the end of the previous segment)
        piece_pts[1..-1].each do |pt|
          path_commands << "L #{pt[0].round(3)} #{pt[1].round(3)}"
        end
      else
        # Use the original curve points as a polyline
        piece_pts = analyzer.piece_points(t_start, t_end)

        piece_data << { piece_num: piece_num, t_start: t_start, t_end: t_end, points: piece_pts }

        # Skip the first point (it's the end of the previous segment)
        piece_pts[1..-1].each do |pt|
          path_commands << "L #{pt[0].round(3)} #{pt[1].round(3)}"
        end
      end
    end

    # Close the path
    path_commands << "Z"

    # Report straightened pieces
    if straightened_pieces.any?
      puts ""
      puts "Straightened Pieces:"
      straightened_pieces.each do |t_start, t_end, piece_num|
        puts "  Piece #{piece_num}: t=#{t_start.round(3)} to #{t_end.round(3)} -> straightened"
      end
    end

    # Report overridden pieces
    if @overridden_pieces && @overridden_pieces.any?
      puts ""
      puts "Overridden Pieces (custom geometry):"
      @overridden_pieces.each do |piece_num, orig_count, new_count|
        puts "  Piece #{piece_num}: #{orig_count} -> #{new_count} points (smooth curve override)"
      end
    end

    { path: path_commands.join(" "), piece_data: piece_data }
  end

  # Build a mapping of piece numbers to their raw t-value ranges
  def build_piece_t_ranges(splits_raw, splits_normalized)
    ranges = []

    # splits_normalized is [0.0, 0.04, 0.115, ...] in lap order
    # Piece N is between splits_normalized[N-1] and splits_normalized[N]
    (0...splits_normalized.length).each do |i|
      piece_num = i + 1
      norm_start = splits_normalized[i]
      norm_end = i + 1 < splits_normalized.length ? splits_normalized[i + 1] : 1.0

      # Convert to raw t-values
      raw_start = (START_FINISH_T - norm_start + 1.0) % 1.0
      raw_end = (START_FINISH_T - norm_end + 1.0) % 1.0

      ranges << { piece_num: piece_num, raw_start: raw_start, raw_end: raw_end, norm_start: norm_start, norm_end: norm_end }
    end

    ranges
  end

  # Find which piece number a given raw t-range belongs to
  def find_piece_number(t_start, t_end, piece_t_ranges)
    mid_t = (t_start + t_end) / 2.0

    piece_t_ranges.each do |range|
      raw_s = range[:raw_start]
      raw_e = range[:raw_end]

      # Raw t goes "backwards" relative to normalized t (because of the subtraction)
      # For non-wrapping pieces: raw_start > raw_end (piece goes from raw_s down to raw_e)
      # For wrapping pieces (crossing t=0): raw_start < raw_end (piece goes from raw_s down through 0 to raw_e)
      if raw_s < raw_e
        # Wrap case: piece spans from raw_s down through 0/1 to raw_e
        # Valid range is [0, raw_s] ∪ [raw_e, 1]
        if mid_t <= raw_s || mid_t >= raw_e
          return range[:piece_num]
        end
      else
        # Normal case (raw_s >= raw_e): piece goes from raw_s down to raw_e
        # Valid range is [raw_e, raw_s]
        if mid_t <= raw_s && mid_t >= raw_e
          return range[:piece_num]
        end
      end
    end

    # Fallback: find closest range
    piece_t_ranges.min_by { |r| [(r[:raw_start] - mid_t).abs, (r[:raw_end] - mid_t).abs].min }[:piece_num]
  end

  # Generate SVG for the track by rendering each piece as individual sidewall polygons
  def generate_track_svg(modified_path_data, default_inner_gap, piece_data, grain_clip_paths)
    svg_parts = []

    # Start with defs section
    svg_parts << "<defs>"
    svg_parts << grain_clip_paths.join("\n")
    svg_parts << "</defs>"

    # Main track group - render each piece as sidewall polygons
    svg_parts << %(<g id="main-track" data-inner-width="#{INNER_TRACK_WIDTH_IN}" data-sidewall-thickness="#{SIDEWALL_THICKNESS_IN}" data-sidewall-height="#{SIDEWALL_HEIGHT_IN}" data-total-width="#{TOTAL_TRACK_WIDTH_IN.round(2)}">)
    svg_parts << %(<!-- Track profile: #{SIDEWALL_THICKNESS_IN}" sidewalls | #{INNER_TRACK_WIDTH_IN}" inner channel | #{SIDEWALL_THICKNESS_IN}" sidewalls = #{TOTAL_TRACK_WIDTH_IN.round(2)}" total -->)

    # Render each piece as constant-width sidewall polygons
    piece_data.each do |pd|
      walls = build_constant_width_piece(pd[:points], INNER_TRACK_WIDTH_IN)
      next unless walls

      svg_parts << %(<!-- Piece #{pd[:piece_num]} -->)
      svg_parts << %(<path d="#{walls[:left]}" fill="#{TRACK_COLOR}" stroke="none"/>)
      svg_parts << %(<path d="#{walls[:right]}" fill="#{TRACK_COLOR}" stroke="none"/>)
    end

    svg_parts << "</g>"

    svg_parts.join("\n")
  end

  # Build constant-width track piece (two sidewall polygons)
  def build_constant_width_piece(points, inner_width)
    return nil if points.nil? || points.length < 2

    total_width = inner_width + (SIDEWALL_THICKNESS_IN * 2)
    half_total = total_width / 2.0
    half_inner = inner_width / 2.0

    outer_left = []
    outer_right = []
    inner_left = []
    inner_right = []

    points.each_with_index do |pt, i|
      # Calculate tangent direction
      if i == 0
        next_pt = points[[1, points.length - 1].min]
        dx = next_pt[0] - pt[0]
        dy = next_pt[1] - pt[1]
      elsif i == points.length - 1
        prev_pt = points[i - 1]
        dx = pt[0] - prev_pt[0]
        dy = pt[1] - prev_pt[1]
      else
        prev_pt = points[i - 1]
        next_pt = points[i + 1]
        dx = next_pt[0] - prev_pt[0]
        dy = next_pt[1] - prev_pt[1]
      end

      len = Math.sqrt(dx * dx + dy * dy)
      next if len < 0.001

      # Perpendicular direction
      norm_x = -dy / len
      norm_y = dx / len

      outer_left << [pt[0] + norm_x * half_total, pt[1] + norm_y * half_total]
      outer_right << [pt[0] - norm_x * half_total, pt[1] - norm_y * half_total]
      inner_left << [pt[0] + norm_x * half_inner, pt[1] + norm_y * half_inner]
      inner_right << [pt[0] - norm_x * half_inner, pt[1] - norm_y * half_inner]
    end

    return nil if outer_left.length < 2

    # Build closed polygons for each sidewall
    left_wall = outer_left + inner_left.reverse
    right_wall = outer_right + inner_right.reverse

    { left: polygon_to_path(left_wall), right: polygon_to_path(right_wall) }
  end

  # Convert an array of points to an SVG path string
  def points_to_path(points)
    return "" if points.nil? || points.empty?

    commands = ["M #{points.first[0].round(3)} #{points.first[1].round(3)}"]
    points[1..-1].each do |pt|
      commands << "L #{pt[0].round(3)} #{pt[1].round(3)}"
    end
    commands.join(" ")
  end

  # Convert a closed polygon to SVG path
  def polygon_to_path(points)
    return "" if points.nil? || points.length < 3

    commands = ["M #{points.first[0].round(3)} #{points.first[1].round(3)}"]
    points[1..-1].each do |pt|
      commands << "L #{pt[0].round(3)} #{pt[1].round(3)}"
    end
    commands << "Z"
    commands.join(" ")
  end

  def generate
    svg_content = File.read(@input_file)

    # Extract path data - look for d= that's preceded by a space (not id=)
    path_match = svg_content.match(/\sd="([^"]+)"/)
    unless path_match
      puts "Error: Could not find path data in SVG"
      return
    end

    path_data = path_match[1]

    # Analyze the track
    analyzer = TrackAnalyzer.new(path_data)

    # Helper to convert normalized t (0.0 = split 1) to raw track t
    # Formula: raw = (START_FINISH_T - normalized + 1.0) mod 1.0
    normalized_to_raw = ->(norm_t) { (START_FINISH_T - norm_t + 1.0) % 1.0 }

    # Build splits from manual configuration (converting from normalized to raw t)
    # Split 1 is at normalized t=0.0, which maps to raw t=START_FINISH_T
    splits_normalized = [0.0] + MANUAL_SPLITS
    splits = splits_normalized.map { |norm_t| normalized_to_raw.call(norm_t) }

    if MANUAL_SPLITS.any?
      puts "Using #{splits.length} manually configured splits"
    else
      puts "WARNING: No manual splits configured. Only split 1 (start/finish) will be shown."
      puts "Add t-values to MANUAL_SPLITS to define piece boundaries."
    end

    puts ""
    puts "Track Analysis:"
    puts "  Total points sampled: #{analyzer.points.length}"
    puts "  Approximate path length: #{analyzer.path_length.round(2)} SVG units"
    puts "  Split points found: #{splits.length}"
    puts ""

    # Generate split lines (no labels on splits - labels go on pieces)
    split_lines = []

    splits.each_with_index do |t, i|
      split_num = i + 1
      point = analyzer.point_at(t)
      tangent = analyzer.tangent_at(t)

      # Perpendicular to tangent
      perp = [-tangent[1], tangent[0]]

      # Create a line perpendicular to the track, contained within track boundaries
      half_len = TRACK_OUTER_WIDTH_IN / 2.0
      x1 = point[0] - perp[0] * half_len
      y1 = point[1] - perp[1] * half_len
      x2 = point[0] + perp[0] * half_len
      y2 = point[1] + perp[1] * half_len

      split_lines << %(<line x1="#{x1.round(3)}" y1="#{y1.round(3)}" x2="#{x2.round(3)}" y2="#{y2.round(3)}" stroke="#{SPLIT_LINE_COLOR}" stroke-width="#{SPLIT_LINE_WIDTH_IN}"/>)

      puts "  Split #{split_num}: t=#{t.round(3)} at (#{point[0].round(1)}, #{point[1].round(1)})"
    end

    # Generate piece labels at the center of each piece (between two splits)
    # Work in normalized coordinates where t=0.0 is split 1 and increases around the lap
    piece_labels = []
    label_font_size_in = 0.8
    label_stroke_width_in = 0.25
    label_color = '#555555'

    splits_normalized.each_with_index do |norm_start, i|
      # Next split in normalized coords (wraps to 1.0 for the last piece)
      norm_end = if i + 1 < splits_normalized.length
        splits_normalized[i + 1]
      else
        1.0  # Last piece goes from final split back to start (t=1.0 same as t=0.0)
      end

      piece_num = i + 1

      # Calculate midpoint in normalized space (simple average, no wrap issues)
      midpoint_norm = (norm_start + norm_end) / 2.0

      # Convert to raw t-value for point lookup
      midpoint_t = normalized_to_raw.call(midpoint_norm)

      # Get the point at the midpoint of the piece
      mid_point = analyzer.point_at(midpoint_t)
      label_x = mid_point[0]
      label_y = mid_point[1]

      # Text with white outline/stroke behind it for readability
      piece_labels << %(<text x="#{label_x.round(2)}" y="#{label_y.round(2)}" fill="white" stroke="white" stroke-width="#{label_stroke_width_in}" font-size="#{label_font_size_in}" font-family="Arial, sans-serif" font-weight="900" text-anchor="middle" dominant-baseline="middle">#{piece_num}</text>)
      piece_labels << %(<text x="#{label_x.round(2)}" y="#{label_y.round(2)}" fill="#{label_color}" font-size="#{label_font_size_in}" font-family="Arial, sans-serif" font-weight="900" text-anchor="middle" dominant-baseline="middle">#{piece_num}</text>)
    end

    # Generate test car visualizations anywhere on track
    # Uses normalized coordinates where t=0.0 is at split 1 (START_FINISH_T)
    test_car_elements = []
    if TEST_CARS.any?
      puts ""
      puts "Test Cars (t=0.0 is split 1, increases around lap):"

      TEST_CARS.each_with_index do |car_config, idx|
        # Get car dimensions based on type
        case car_config[:type]
        when :premium
          car_length = PREMIUM_CAR_LENGTH_IN
          car_width = PREMIUM_CAR_WIDTH_IN
        when :mainline
          car_length = MAINLINE_CAR_LENGTH_IN
          car_width = MAINLINE_CAR_WIDTH_IN
        when :lego
          car_length = LEGO_CAR_LENGTH_IN
          car_width = LEGO_CAR_WIDTH_IN
        else
          car_length = PREMIUM_CAR_LENGTH_IN
          car_width = PREMIUM_CAR_WIDTH_IN
        end

        # Convert normalized t (0.0 = split 1) to raw track t
        raw_t = normalized_to_raw.call(car_config[:t])
        car_point = analyzer.point_at(raw_t)
        car_tangent = analyzer.tangent_at(raw_t)

        # Calculate rotation angle from tangent
        angle_rad = Math.atan2(car_tangent[1], car_tangent[0])
        angle_deg = angle_rad * 180.0 / Math::PI

        # Create rectangle centered on track, rotated to follow tangent
        half_length = car_length / 2.0
        half_width = car_width / 2.0
        car_color = TEST_CAR_COLORS[car_config[:type]] || '#00AA00'

        test_car_elements << %(<rect x="#{(-half_length).round(3)}" y="#{(-half_width).round(3)}" width="#{car_length.round(3)}" height="#{car_width.round(3)}" fill="#{car_color}" fill-opacity="#{TEST_CAR_OPACITY}" stroke="#{car_color}" stroke-width="0.05" transform="translate(#{car_point[0].round(3)}, #{car_point[1].round(3)}) rotate(#{angle_deg.round(2)})"/>)

        puts "  Car #{idx + 1}: #{car_config[:type]} at normalized t=#{car_config[:t].round(3)} (raw t=#{raw_t.round(3)})"
      end
    end

    # Generate grain direction visualization for each piece
    grain_lines = []
    if SHOW_GRAIN_DIRECTION && splits.length > 1
      puts ""
      puts "Grain Direction Analysis:"

      # For each piece between consecutive splits (in display order)
      (0...splits.length).each do |i|
        t1 = splits[i]
        t2 = splits[(i + 1) % splits.length]

        # Determine actual t_start and t_end for the track segment
        t_low = [t1, t2].min
        t_high = [t1, t2].max

        # Check if this is a wrap-around piece (gap > 0.5 means shorter path wraps through 0)
        is_wraparound = (t_high - t_low) > 0.5

        if is_wraparound
          # Wrap-around case: piece goes from t_high to 1.0 and 0.0 to t_low
          # Combine both segments for grain calculation
          pts_high = analyzer.piece_points(t_high, 1.0)
          pts_low = analyzer.piece_points(0.0, t_low)
          piece_pts = pts_high + pts_low

          # Calculate bounds from combined points
          if piece_pts && piece_pts.length > 2
            all_x = piece_pts.map { |p| p[0] }
            all_y = piece_pts.map { |p| p[1] }
            bounds = {
              min_x: all_x.min, max_x: all_x.max,
              min_y: all_y.min, max_y: all_y.max
            }

            # Use the larger segment for grain direction
            if (1.0 - t_high) > t_low
              grain_dir = analyzer.optimal_grain_direction(t_high, 1.0)
            else
              grain_dir = analyzer.optimal_grain_direction(0.0, t_low)
            end
          else
            next
          end

          actual_start, actual_end = t_high, t_low  # For display purposes
        else
          actual_start, actual_end = t_low, t_high
          grain_dir = analyzer.optimal_grain_direction(actual_start, actual_end)
          bounds = analyzer.piece_bounds(actual_start, actual_end)
          piece_pts = analyzer.piece_points(actual_start, actual_end)
        end

        next unless bounds && piece_pts && piece_pts.length > 2

        # Calculate grain angle in degrees for display
        grain_angle = Math.atan2(grain_dir[1], grain_dir[0]) * 180 / Math::PI

        piece_num = i + 1
        if is_wraparound
          puts "  Piece #{piece_num}: t=#{t_high.round(3)}→1.0→0.0→#{t_low.round(3)} (wrap), grain angle: #{grain_angle.round(1)}°"
        else
          puts "  Piece #{piece_num}: t=#{actual_start.round(3)}-#{actual_end.round(3)}, grain angle: #{grain_angle.round(1)}°"
        end

        # Generate grain lines
        grain_lines << generate_grain_lines_for_piece(grain_dir, bounds, piece_pts, path_data, actual_start, actual_end)
      end
    end

    # Tight radius warnings will be calculated later from piece_data (the modified/edit path)
    tight_warnings = []

    # Calculate dimensions from actual track bounds (not original SVG)
    track_all_x = analyzer.points.map { |p| p[0] }
    track_all_y = analyzer.points.map { |p| p[1] }
    track_min_x = track_all_x.min
    track_max_x = track_all_x.max
    track_min_y = track_all_y.min
    track_max_y = track_all_y.max

    # Add margin for dimension lines and labels (in inches)
    dim_margin_in = 4.0  # Space for dimension lines below and to the right

    # Calculate viewbox based on track bounds + margins (all in inches now)
    # Align viewbox to whole inches so grid has no partial cells on edges
    raw_viewbox_x = track_min_x - SVG_PADDING_IN
    raw_viewbox_y = track_min_y - SVG_PADDING_IN
    raw_viewbox_right = track_max_x + SVG_PADDING_IN + dim_margin_in
    raw_viewbox_bottom = track_max_y + SVG_PADDING_IN + dim_margin_in

    # Round to whole inches: origin down, edges up
    viewbox_x = raw_viewbox_x.floor
    viewbox_y = raw_viewbox_y.floor
    viewbox_width = raw_viewbox_right.ceil - viewbox_x
    viewbox_height = raw_viewbox_bottom.ceil - viewbox_y

    padded_viewbox = [viewbox_x, viewbox_y, viewbox_width, viewbox_height].join(' ')

    # SVG pixel dimensions (1:1 with viewbox units)
    padded_width = viewbox_width
    padded_height = viewbox_height

    # Build modified SVG with padding
    # Create a background rect that covers the viewbox area
    bg_rect = %(<rect x="#{viewbox_x}" y="#{viewbox_y}" width="#{viewbox_width}" height="#{viewbox_height}" fill="white"/>)

    # Create background grid pattern (1" x 1" subtle grid)
    # With patternUnits="userSpaceOnUse", grid lines naturally align to whole numbers in user space
    grid_defs = ""
    grid_rect = ""
    if SHOW_BACKGROUND_GRID
      grid_defs = %(<defs>
<pattern id="background-grid" width="#{GRID_SIZE_IN}" height="#{GRID_SIZE_IN}" patternUnits="userSpaceOnUse">
<path d="M #{GRID_SIZE_IN} 0 L 0 0 0 #{GRID_SIZE_IN}" fill="none" stroke="#{GRID_COLOR}" stroke-width="#{GRID_LINE_WIDTH_IN}"/>
</pattern>
</defs>)
      grid_rect = %(<rect x="#{viewbox_x}" y="#{viewbox_y}" width="#{viewbox_width}" height="#{viewbox_height}" fill="url(#background-grid)"/>)
    end
    split_group = %(<g id="split-lines">\n#{split_lines.join("\n")}\n</g>)
    label_group = %(<g id="piece-labels">\n#{piece_labels.join("\n")}\n</g>)

    # Create ghost track if enabled - shows ORIGINAL track layout scaled to match output
    # This lets you compare the original curves vs simplified output at the same size
    ghost_track = ""
    if SHOW_GHOST_TRACK
      ghost_style = GHOST_TRACK_STYLE == 'dashed' ? 'stroke-dasharray="10,5"' : ''

      if SCALING_MODE != :none && analyzer.scale_factor != 1.0
        # The scaled track's center = original track's center (scaling preserves center)
        # Use the track bounds already calculated above
        center_x = (track_min_x + track_max_x) / 2.0
        center_y = (track_min_y + track_max_y) / 2.0

        scale = analyzer.scale_factor
        # Transform: move to origin, scale, move back to center
        # Since scaling preserves the center, we use the same center for both translates
        ghost_track = %(<g id="ghost-track" opacity="#{GHOST_TRACK_OPACITY}" transform="translate(#{center_x}, #{center_y}) scale(#{scale}) translate(#{-center_x}, #{-center_y})">
<path d="#{path_data}" stroke="#{GHOST_TRACK_COLOR}" stroke-width="#{GHOST_TRACK_WIDTH_IN / scale}" fill="none" #{ghost_style}/>
</g>)
      else
        ghost_track = %(<g id="ghost-track" opacity="#{GHOST_TRACK_OPACITY}">
<path d="#{path_data}" stroke="#{GHOST_TRACK_COLOR}" stroke-width="#{GHOST_TRACK_WIDTH_IN}" fill="none" #{ghost_style}/>
</g>)
      end
    end


    # Create U-shaped track profile: two sidewalls with inner channel between them
    # The mask creates the channel by subtracting the inner width from the total width
    inner_gap_width = INNER_TRACK_WIDTH_IN

    # Extract clip paths from grain lines (they go in <defs>)
    grain_clip_paths = []
    grain_groups = []
    grain_lines.each do |gl|
      # Split into clip path and group parts
      if gl =~ /(<clipPath[^>]*>.*?<\/clipPath>)/m
        grain_clip_paths << $1
      end
      if gl =~ /(<g clip-path[^>]*>.*?<\/g>)/m
        grain_groups << $1
      end
    end

    # Build a custom path that straightens "straight enough" pieces
    # We need to generate path data for each piece
    path_result = build_modified_path(analyzer, splits, path_data, splits_normalized)
    modified_path_data = path_result[:path]
    piece_data = path_result[:piece_data]

    # Find and visualize tight radius sections on the EDIT PATH (modified path)
    if SHOW_TIGHT_RADIUS_WARNINGS
      tight_sections = PieceOverrideGenerator.find_tight_sections_in_piece_data(piece_data, TIGHT_RADIUS_THRESHOLD_IN)

      if tight_sections.any?
        puts ""
        puts "TIGHT RADIUS WARNINGS on edit path (< #{TIGHT_RADIUS_THRESHOLD_IN}\" min radius):"
        tight_sections.each_with_index do |section, i|
          pt = section[:center_point]
          puts "  ##{i+1}: piece #{section[:piece_num]}, radius=#{section[:min_radius].round(2)}\" at (#{pt[0].round(1)}, #{pt[1].round(1)})"

          marker_r = 0.8
          tight_warnings << %(<circle cx="#{pt[0].round(2)}" cy="#{pt[1].round(2)}" r="#{marker_r}" fill="none" stroke="#{TIGHT_RADIUS_COLOR}" stroke-width="0.1"/>)
          tight_warnings << %(<text x="#{pt[0].round(2)}" y="#{(pt[1] - marker_r - 0.2).round(2)}" fill="#{TIGHT_RADIUS_COLOR}" font-size="0.5" font-family="Arial" text-anchor="middle">#{section[:min_radius].round(1)}"</text>)
        end
      else
        puts ""
        puts "All turn radii on edit path OK (>= #{TIGHT_RADIUS_THRESHOLD_IN}\")"
      end
    end

    # Create edit path - the blue centerline for curve editing
    # This shows the OUTPUT path (after straightening/smoothing) that will be used for sidewalls
    edit_path = ""
    if SHOW_EDIT_PATH
      edit_path = %(<g id="edit-path">
<path d="#{modified_path_data}" stroke="#{EDIT_PATH_COLOR}" stroke-width="#{EDIT_PATH_WIDTH_IN}" fill="none" opacity="#{EDIT_PATH_OPACITY}"/>
</g>)
    end

    # Generate per-piece track rendering (handles custom widths internally)
    # Only render sidewalls if enabled
    main_track = ""
    if SHOW_SIDEWALLS
      main_track = generate_track_svg(modified_path_data, inner_gap_width, piece_data, grain_clip_paths)
    end

    # Create grain direction group - uses per-piece polygon clip paths
    # Only render grain if enabled
    grain_group = ""
    if SHOW_WOOD_GRAIN && grain_groups.any?
      grain_group = %(<g id="grain-direction">\n#{grain_groups.join("\n")}\n</g>)
    end

    # Create scale bar in lower left corner
    scale_bar = ""
    if SHOW_SCALE_BAR
      scale_length = 12.0  # 12 inches (1 foot) - output is in inches so 1 unit = 1 inch
      margin_in = 1.5

      # Position in lower left of padded viewbox, aligned to grid
      bar_x = (viewbox_x + margin_in).ceil  # Align to next whole inch (grid line)
      bar_y = viewbox_y + viewbox_height - margin_in

      tick_height = 0.2
      stroke_width = 0.05
      font_size = 0.8

      # Scale bar: horizontal line with end caps
      scale_bar = %(<g id="scale-bar">
<rect x="#{bar_x}" y="#{bar_y - SCALE_BAR_HEIGHT_IN}" width="#{scale_length}" height="#{SCALE_BAR_HEIGHT_IN}" fill="#{SCALE_BAR_COLOR}"/>
<line x1="#{bar_x}" y1="#{bar_y - SCALE_BAR_HEIGHT_IN - tick_height}" x2="#{bar_x}" y2="#{bar_y + tick_height}" stroke="#{SCALE_BAR_COLOR}" stroke-width="#{stroke_width}"/>
<line x1="#{bar_x + scale_length}" y1="#{bar_y - SCALE_BAR_HEIGHT_IN - tick_height}" x2="#{bar_x + scale_length}" y2="#{bar_y + tick_height}" stroke="#{SCALE_BAR_COLOR}" stroke-width="#{stroke_width}"/>
<text x="#{bar_x + scale_length / 2}" y="#{bar_y - SCALE_BAR_HEIGHT_IN - 0.3}" fill="#{SCALE_BAR_COLOR}" font-size="#{font_size}" font-family="Arial, sans-serif" text-anchor="middle">1 foot</text>
</g>)
    end

    # Create overall dimension lines (width and height)
    dimension_lines = ""
    if SHOW_SCALE_BAR
      # Use track bounds already calculated above
      # Output coordinates are already in inches (1 unit = 1 inch)
      width_inches = track_max_x - track_min_x
      height_inches = track_max_y - track_min_y

      # Format as feet and inches
      def format_feet_inches(inches)
        feet = (inches / 12).floor
        remaining_inches = (inches % 12).round
        if feet > 0
          "#{feet}' #{remaining_inches}\""
        else
          "#{remaining_inches}\""
        end
      end

      # Align dimension endpoints to grid lines (whole inches)
      dim_min_x = track_min_x.floor  # Round down to align with vertical grid line
      dim_max_x = track_max_x.ceil   # Round up to align with vertical grid line
      dim_min_y = track_min_y.floor  # Round down to align with horizontal grid line
      dim_max_y = track_max_y.ceil   # Round up to align with horizontal grid line

      # Recalculate dimensions based on grid-aligned endpoints
      aligned_width = dim_max_x - dim_min_x
      aligned_height = dim_max_y - dim_min_y
      width_label = format_feet_inches(aligned_width)
      height_label = format_feet_inches(aligned_height)

      dim_color = SCALE_BAR_COLOR
      dim_offset_in = 2.0   # Distance from track edge (inches)
      tick_size_in = 0.5    # Tick mark size (inches)
      stroke_width_in = 0.05
      font_size_in = 0.8

      # Width dimension (below track) - aligned to grid
      w_y = track_max_y + dim_offset_in
      # Height dimension (right of track) - aligned to grid
      h_x = track_max_x + dim_offset_in

      dimension_lines = %(<g id="dimensions" fill="#{dim_color}" stroke="#{dim_color}" stroke-width="#{stroke_width_in}">
<!-- Width dimension - aligned to grid at #{dim_min_x}" and #{dim_max_x}" -->
<line x1="#{dim_min_x}" y1="#{w_y}" x2="#{dim_max_x}" y2="#{w_y}"/>
<line x1="#{dim_min_x}" y1="#{w_y - tick_size_in/2}" x2="#{dim_min_x}" y2="#{w_y + tick_size_in/2}"/>
<line x1="#{dim_max_x}" y1="#{w_y - tick_size_in/2}" x2="#{dim_max_x}" y2="#{w_y + tick_size_in/2}"/>
<text x="#{(dim_min_x + dim_max_x) / 2}" y="#{w_y + 1.0}" font-size="#{font_size_in}" font-family="Arial, sans-serif" text-anchor="middle" stroke="none">#{width_label}</text>
<!-- Height dimension - aligned to grid at #{dim_min_y}" and #{dim_max_y}" -->
<line x1="#{h_x}" y1="#{dim_min_y}" x2="#{h_x}" y2="#{dim_max_y}"/>
<line x1="#{h_x - tick_size_in/2}" y1="#{dim_min_y}" x2="#{h_x + tick_size_in/2}" y2="#{dim_min_y}"/>
<line x1="#{h_x - tick_size_in/2}" y1="#{dim_max_y}" x2="#{h_x + tick_size_in/2}" y2="#{dim_max_y}"/>
<text x="#{h_x + 0.5}" y="#{(dim_min_y + dim_max_y) / 2}" font-size="#{font_size_in}" font-family="Arial, sans-serif" text-anchor="start" dominant-baseline="middle" stroke="none">#{height_label}</text>
</g>)
    end

    # Update SVG dimensions and viewBox
    # ViewBox stays in inches (for CNC compatibility)
    # Width/height are scaled up for comfortable viewing (SVG_DISPLAY_SCALE pixels per inch)
    modified_svg = svg_content.dup
    display_width = (padded_width * SVG_DISPLAY_SCALE).round(2)
    display_height = (padded_height * SVG_DISPLAY_SCALE).round(2)
    modified_svg = modified_svg.sub(/width="[^"]+"/, %(width="#{display_width}"))
    modified_svg = modified_svg.sub(/height="[^"]+"/, %(height="#{display_height}"))
    modified_svg = modified_svg.sub(/viewBox="[^"]+"/, %(viewBox="#{padded_viewbox}"))

    # Remove the original path element - we'll replace it with our styled tracks
    modified_svg = modified_svg.sub(/<path[^>]+\/>/, '')

    # Build content: background, grid, ghost track, edit path, main track
    # Order: ghost track (red, original) -> edit path (blue, modified centerline) -> main track (sidewalls)
    insert_content = "#{grid_defs}\n#{bg_rect}\n#{grid_rect}\n#{ghost_track}\n#{edit_path}\n#{main_track}"

    # Insert after opening <svg ...> tag (find the svg tag and insert after it)
    modified_svg = modified_svg.sub(/(<svg[^>]*>)/, "\\1\n#{insert_content}\n")

    # Build tight radius warnings group
    warnings_group = ""
    if tight_warnings.any?
      warnings_group = %(<g id="tight-radius-warnings">\n#{tight_warnings.join("\n")}\n</g>)
    end

    # Build turn markers group (for piece 3 chicane visualization)
    turn_markers_group = ""
    markers = PieceOverrideGenerator.turn_markers
    if markers && markers.any?
      marker_elements = markers.map do |m|
        pt = m[:pt]
        dir = m[:dir]
        label = m[:label]
        # Draw a small perpendicular hash mark
        perp = [-dir[1], dir[0]]  # Perpendicular to direction
        half_len = 0.4  # Half length of hash mark
        x1 = pt[0] + perp[0] * half_len
        y1 = pt[1] + perp[1] * half_len
        x2 = pt[0] - perp[0] * half_len
        y2 = pt[1] - perp[1] * half_len
        # Orange color for turn markers - hash mark + label
        line = %(<line x1="#{x1.round(2)}" y1="#{y1.round(2)}" x2="#{x2.round(2)}" y2="#{y2.round(2)}" stroke="#FF6600" stroke-width="0.08"/>)
        text = %(<text x="#{(pt[0] + perp[0] * 0.7).round(2)}" y="#{(pt[1] + perp[1] * 0.7).round(2)}" fill="#FF6600" font-size="0.35" font-family="Arial" text-anchor="middle" dominant-baseline="middle">#{label}</text>)
        line + "\n" + text
      end
      turn_markers_group = %(<g id="turn-markers">\n#{marker_elements.join("\n")}\n</g>)
    end

    # Build test cars group - only if enabled
    test_cars_group = ""
    if SHOW_TEST_CARS && test_car_elements.any?
      test_cars_group = %(<g id="test-cars">\n#{test_car_elements.join("\n")}\n</g>)
    end

    # Insert grain direction, split lines, labels, scale bar, warnings, turn markers, and test cars before closing </svg>
    # Order matters for SVG layering - later elements render on top
    modified_svg = modified_svg.sub(/<\/svg>/, "#{grain_group}\n#{split_group}\n#{test_cars_group}\n#{scale_bar}\n#{dimension_lines}\n#{warnings_group}\n#{turn_markers_group}\n#{label_group}\n</svg>")

    File.write(@output_file, modified_svg)

    puts ""
    puts "Generated #{@output_file} with #{splits.length} split indicators"
    puts ""
    puts "Piece count: #{splits.length} pieces"
  end
end

#===============================================================================
# MAIN
#===============================================================================

unless File.exist?(INPUT_FILE)
  puts "Error: File not found: #{INPUT_FILE}"
  exit 1
end

visualizer = SplitVisualizer.new(INPUT_FILE, OUTPUT_FILE)
visualizer.generate

puts ""
print 'Opening in Cursor...'
system("cursor", OUTPUT_FILE)
