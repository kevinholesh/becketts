#!/usr/bin/env ruby

# Silverstone F1 Track Piece Generator
# Generates SVG pieces for CNC cutting from walnut wood
# Optimized for Hot Wheels Premium F1 cars

require_relative 'blue_track_builder'

#===============================================================================
# CONFIGURATION
#===============================================================================

# Input/Output files
INPUT_FILE = 'silverstone.svg'
OUTPUT_FILE = 'silverstone-split.svg'
PIECES_FILE = 'pieces.svg'
PIECES_LAYED_OUT_FILE = 'pieces-layed-out.svg'

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
SIDEWALL_THICKNESS_IN = 0.2  # Thickness of each side wall
SIDEWALL_HEIGHT_IN = 0.375     # Height of the side walls

# Total track width = inner channel + two sidewalls
TOTAL_TRACK_WIDTH_IN = INNER_TRACK_WIDTH_IN + (SIDEWALL_THICKNESS_IN * 2)

# Convert inner edge radius to centerline radius
def centerline_radius_from_inner_edge_radius(inner_edge_radius)
  inner_edge_radius + INNER_TRACK_WIDTH_IN / 2.0
end

# Turning constraints (in inches)
# Minimum radius should be at least 1.5x car length for smooth turns
MIN_TURN_RADIUS_IN = 2.5 # Centerline
COMFORTABLE_TURN_RADIUS_IN = 3.5

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

#===============================================================================
# BLUE TRACK PRIMITIVE CHAIN
#===============================================================================
# This defines the blue (edit) track as a sequence of arcs and straights.
# Edit these values to reshape the track. The red ghost track shows the original.
#
# Each primitive is either:
#   { type: :straight, length: X }           - straight segment of X inches
#   { type: :straight, length: X, angle: A }        - straight at absolute angle A (0=right, 90=down)
#   { type: :straight, length: X, angle_offset: O } - straight rotated O degrees from current dir
#   { type: :turn, radius: R, angle: A, direction: :left/:right }  - arc segment
#
# Net turn angle should sum to ~360 (clockwise) or ~-360 (counter-clockwise)
# for the track to close properly.

# IMPORTANT: Never overwrite this definition...
BLUE_TRACK_DEFINITION = [
  { type: :straight, length: 13.6, angle_offset: -4.7 },
  { type: :turn, radius: 5, angle: 62.0, direction: :right },
  { type: :straight, length: 2.7 },
  { type: :turn, radius: 5, angle: 47.0, direction: :left },
  { type: :straight, length: 3.5 },
  { type: :turn, radius: MIN_TURN_RADIUS_IN, angle: 110.0, direction: :right },
  { type: :straight, length: 0 },
  { type: :turn, radius: MIN_TURN_RADIUS_IN, angle: 160.0, direction: :left },
  { type: :straight, length: 1.4 },
  { type: :turn, radius: 4.5, angle: 50, direction: :left },
  { type: :straight, length: 22.5 },
  { type: :turn, radius: MIN_TURN_RADIUS_IN, angle: 132, direction: :left },
  { type: :straight, length: 0.5 },
  { type: :turn, radius: MIN_TURN_RADIUS_IN, angle: 212, direction: :right },
  { type: :straight, length: 6.8 },
  { type: :turn, radius: 5, angle: 51, direction: :right },
  { type: :straight, length: 15.3 },
  { type: :turn, radius: 5, angle: 90, direction: :right },
  { type: :straight, length: 13 },
  # { type: :turn, radius: 100, angle: 7, direction: :right },
  { type: :turn, radius: 9, angle: 20, direction: :left },
  { type: :straight, length: 1 },
  { type: :turn, radius: 4.3, angle: 50, direction: :right },
  { type: :straight, length: 1.2 },
  { type: :turn, radius: 4.5, angle: 63, direction: :left },
  { type: :straight, length: 0.2 },
  { type: :turn, radius: 3.1, angle: 97, direction: :right },
  { type: :straight, length: 2 },
  { type: :turn, radius: 7, angle: 27.9, direction: :left },
  { type: :straight, length: 26.5 },
  { type: :turn, radius: 3.3, angle: 100, direction: :right },
  { type: :turn, radius: 5, angle: 30, direction: :right },
  { type: :turn, radius: 5, angle: 13, direction: :left },
  { type: :straight, length: 9.65 },
  { type: :turn, radius: MIN_TURN_RADIUS_IN, angle: 100, direction: :left },
  { type: :turn, radius: 3, angle: 171, direction: :right },
  { type: :straight, length: 4 },
]

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
  0.06,
  0.13,
  0.215,
  0.31,
  # # 0.365, # Maybe rethink this one
  0.425,
  0.524,
  0.595,
  0.715,
  0.84,
  0.915,
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
EDIT_PATH_WIDTH_IN = 0.8         # Thicker line for visibility
EDIT_PATH_OPACITY = 0.5          # Semi-transparent for overlay
EDIT_PATH_MULTI_COLOR = false    # Different shade of blue for each primitive (helps with tracing)

# Rendering toggles - disable to focus on path editing
SHOW_SIDEWALLS = true            # Render the U-shaped track profile
SHOW_TEST_CARS = false            # Render test car visualizations
SHOW_WOOD_GRAIN = true           # Render grain direction lines

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
# TRACK ANALYSIS UTILITIES
#===============================================================================

class TrackAnalysisUtils
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

  # Build a modified path from the BLUE_TRACK_DEFINITION primitive chain
  # Returns: { path: String, piece_data: Array of {piece_num, t_start, t_end, points} }
  def build_modified_path(analyzer, splits, original_path_data, splits_normalized)
    build_path_from_definition(analyzer, splits_normalized)
  end

  # Build the entire blue track from BLUE_TRACK_DEFINITION and split it into pieces
  def build_path_from_definition(analyzer, splits_normalized)
    # Get starting point and direction from the red track at START_FINISH_T
    start_pt = analyzer.point_at(START_FINISH_T)
    start_tangent = analyzer.tangent_at(START_FINISH_T)

    # Racing direction is opposite to raw t direction, so negate the tangent
    start_dir = [-start_tangent[0], -start_tangent[1]]

    puts ""
    puts "Building blue track from BLUE_TRACK_DEFINITION (#{BLUE_TRACK_DEFINITION.length} primitives)"

    # Build the complete blue track
    builder = BlueTrackBuilder.new(BLUE_TRACK_DEFINITION, start_pt, start_dir)
    all_points = builder.build

    closure_gap = builder.closure_gap
    puts "  Generated #{all_points.length} points, total length: #{builder.path_length.round(2)}\""
    puts "  Closure gap: #{closure_gap.round(2)}\" (track end to start distance)"
    if closure_gap > 1.0
      puts "  WARNING: Track does not close properly. Adjust primitive angles/radii to close the loop."
    end

    # Calculate cumulative distances along the track for splitting
    cumulative_dist = [0.0]
    (1...all_points.length).each do |i|
      dx = all_points[i][0] - all_points[i-1][0]
      dy = all_points[i][1] - all_points[i-1][1]
      cumulative_dist << cumulative_dist.last + Math.sqrt(dx*dx + dy*dy)
    end
    total_length = cumulative_dist.last

    # Split the track into pieces based on normalized t values
    # splits_normalized is [0.0, 0.04, 0.115, ...] where each value is a fraction of the lap
    num_pieces = splits_normalized.length
    piece_data = []

    (1..num_pieces).each do |piece_num|
      norm_start = splits_normalized[piece_num - 1]
      norm_end = piece_num < num_pieces ? splits_normalized[piece_num] : 1.0

      # Convert normalized t to distance along the blue track
      dist_start = norm_start * total_length
      dist_end = norm_end * total_length

      # Find point indices for this piece
      start_idx = cumulative_dist.index { |d| d >= dist_start } || 0
      end_idx = cumulative_dist.index { |d| d >= dist_end } || (all_points.length - 1)

      # Ensure we have at least 2 points
      end_idx = [end_idx, start_idx + 1].max if end_idx <= start_idx

      # Extract points for this piece
      piece_pts = all_points[start_idx..end_idx]

      # Convert to raw t values for compatibility with the rest of the system
      raw_start = (START_FINISH_T - norm_start + 1.0) % 1.0
      raw_end = (START_FINISH_T - norm_end + 1.0) % 1.0

      # Points are in racing order, but piece_data expects raw-t order (reversed)
      piece_data << {
        piece_num: piece_num,
        t_start: raw_end,    # In raw-t order, piece starts at raw_end
        t_end: raw_start,    # and ends at raw_start
        points: piece_pts.reverse  # Reverse to raw-t order
      }
    end

    # Build SVG path from all points
    path_commands = []
    if all_points.any?
      # Reverse to raw-t order for SVG path
      raw_t_points = all_points.reverse
      first_pt = raw_t_points.first
      path_commands << "M #{first_pt[0].round(3)} #{first_pt[1].round(3)}"
      raw_t_points[1..-1].each do |pt|
        path_commands << "L #{pt[0].round(3)} #{pt[1].round(3)}"
      end
    end
    # Don't close the path - leave it open for manual tracing
    # path_commands << "Z"

    { path: path_commands.join(" "), piece_data: piece_data, primitive_segments: builder.segments }
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

    # Split lines will be generated later from piece_data (the blue edit path)
    # This ensures split lines appear on the actual track being built, not the ghost track
    split_lines = []

    # Piece labels will be generated later after piece_data is available
    # (so labels align with the blue edit path for overridden pieces)
    piece_labels = []

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

    # Grain direction visualization will be generated after piece_data is available
    # (so grain aligns with the blue edit path, not the original ghost track)
    grain_lines = []

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
    # split_group will be created later after split_lines is populated from piece_data

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
    primitive_segments = path_result[:primitive_segments] || []

    # Generate split lines from piece_data (the blue edit path)
    # Each piece's first point (in raw-t order) is where the split line should be
    puts ""
    puts "Split Points (from edit path):"
    piece_data.each do |pd|
      split_num = pd[:piece_num]
      points = pd[:points]
      next if points.empty?

      # The first point of each piece is the split location
      point = points.first

      # Calculate tangent from first two points
      if points.length >= 2
        dx = points[1][0] - points[0][0]
        dy = points[1][1] - points[0][1]
        len = Math.sqrt(dx * dx + dy * dy)
        if len > 0.001
          tangent = [dx / len, dy / len]
        else
          tangent = [1.0, 0.0]
        end
      else
        tangent = [1.0, 0.0]
      end

      # Perpendicular to tangent
      perp = [-tangent[1], tangent[0]]

      # Create a line perpendicular to the track
      half_len = TRACK_OUTER_WIDTH_IN / 2.0
      x1 = point[0] - perp[0] * half_len
      y1 = point[1] - perp[1] * half_len
      x2 = point[0] + perp[0] * half_len
      y2 = point[1] + perp[1] * half_len

      split_lines << %(<line x1="#{x1.round(3)}" y1="#{y1.round(3)}" x2="#{x2.round(3)}" y2="#{y2.round(3)}" stroke="#{SPLIT_LINE_COLOR}" stroke-width="#{SPLIT_LINE_WIDTH_IN}"/>)

      puts "  Split #{split_num}: at (#{point[0].round(1)}, #{point[1].round(1)})"
    end

    # Create split_group now that split_lines is populated
    split_group = %(<g id="split-lines">\n#{split_lines.join("\n")}\n</g>)

    # Now generate grain direction using piece_data (the blue edit path)
    if SHOW_GRAIN_DIRECTION && piece_data.any?
      puts ""
      puts "Grain Direction Analysis:"

      # Group piece_data by piece_num (wrap-around pieces may have multiple segments)
      pieces_by_num = {}
      piece_data.each do |pd|
        pieces_by_num[pd[:piece_num]] ||= []
        pieces_by_num[pd[:piece_num]] << pd
      end

      pieces_by_num.each do |piece_num, segments|
        # Combine all points for this piece
        piece_pts = segments.flat_map { |s| s[:points] }
        next if piece_pts.length < 2

        # Calculate bounds
        all_x = piece_pts.map { |p| p[0] }
        all_y = piece_pts.map { |p| p[1] }
        bounds = {
          min_x: all_x.min, max_x: all_x.max,
          min_y: all_y.min, max_y: all_y.max
        }

        # Calculate grain direction from piece points (sum of tangent vectors)
        sum_x = 0.0
        sum_y = 0.0
        ref_dir = nil
        (0...piece_pts.length - 1).each do |i|
          dx = piece_pts[i + 1][0] - piece_pts[i][0]
          dy = piece_pts[i + 1][1] - piece_pts[i][1]
          len = Math.sqrt(dx * dx + dy * dy)
          next if len < 0.0001
          dx /= len
          dy /= len

          # Use first tangent as reference, flip others if they point opposite
          if ref_dir.nil?
            ref_dir = [dx, dy]
            sum_x += dx
            sum_y += dy
          else
            dot = dx * ref_dir[0] + dy * ref_dir[1]
            if dot < 0
              sum_x -= dx
              sum_y -= dy
            else
              sum_x += dx
              sum_y += dy
            end
          end
        end

        # Normalize
        len = Math.sqrt(sum_x * sum_x + sum_y * sum_y)
        grain_dir = len > 0.0001 ? [sum_x / len, sum_y / len] : [1.0, 0.0]

        # Calculate grain angle
        grain_angle = Math.atan2(grain_dir[1], grain_dir[0]) * 180 / Math::PI

        # Get t values for display
        t_start = segments.first[:t_start]
        t_end = segments.last[:t_end]
        is_wraparound = segments.length > 1

        if is_wraparound
          puts "  Piece #{piece_num}: t=#{t_start.round(3)}→1.0→0.0→#{t_end.round(3)} (wrap), grain angle: #{grain_angle.round(1)}°"
        else
          puts "  Piece #{piece_num}: t=#{t_start.round(3)}-#{t_end.round(3)}, grain angle: #{grain_angle.round(1)}°"
        end

        # Generate grain lines using the edit path points
        grain_lines << generate_grain_lines_for_piece(grain_dir, bounds, piece_pts, path_data, t_start, t_end)
      end
    end

    # Re-extract clip paths from grain lines now that they're populated
    grain_clip_paths = []
    grain_groups = []
    grain_lines.each do |gl|
      if gl =~ /(<clipPath[^>]*>.*?<\/clipPath>)/m
        grain_clip_paths << $1
      end
      if gl =~ /(<g clip-path[^>]*>.*?<\/g>)/m
        grain_groups << $1
      end
    end

    # Find and visualize tight radius sections on the EDIT PATH (modified path)
    if SHOW_TIGHT_RADIUS_WARNINGS
      tight_sections = TrackAnalysisUtils.find_tight_sections_in_piece_data(piece_data, TIGHT_RADIUS_THRESHOLD_IN)

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
      if EDIT_PATH_MULTI_COLOR && primitive_segments.any?
        # Draw each primitive segment in a different shade of blue
        segment_paths = primitive_segments.map.with_index do |seg, i|
          pts = seg[:points]
          next nil if pts.nil? || pts.length < 2

          # Generate different shades of blue based on segment index
          # Cycle through hues from cyan (180) to blue (240) to purple (280)
          hue = 200 + (i * 31) % 80  # Varies from 200 to 280
          saturation = 70 + (i * 13) % 30  # 70-100%
          lightness = 40 + (i * 11) % 25   # 40-65%
          color = "hsl(#{hue}, #{saturation}%, #{lightness}%)"

          # Build path for this segment
          path_d = "M #{pts[0][0].round(3)} #{pts[0][1].round(3)}"
          pts[1..-1].each { |pt| path_d += " L #{pt[0].round(3)} #{pt[1].round(3)}" }

          %(<path d="#{path_d}" stroke="#{color}" stroke-width="#{EDIT_PATH_WIDTH_IN}" fill="none" opacity="#{EDIT_PATH_OPACITY}" data-segment="#{i + 1}" data-type="#{seg[:type]}"/>)
        end.compact

        edit_path = %(<g id="edit-path">\n#{segment_paths.join("\n")}\n</g>)
      else
        # Single color for entire path
        edit_path = %(<g id="edit-path">
<path d="#{modified_path_data}" stroke="#{EDIT_PATH_COLOR}" stroke-width="#{EDIT_PATH_WIDTH_IN}" fill="none" opacity="#{EDIT_PATH_OPACITY}"/>
</g>)
      end
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

    # Generate piece labels at the center of each piece
    # Uses piece_data to get actual points (including overridden geometry)
    # Group by piece_num first (wrap-around pieces like 6 may have multiple segments)
    label_font_size_in = 0.8
    label_stroke_width_in = 0.25
    label_color = '#555555'

    # Group all points by piece number
    points_by_piece = {}
    piece_data.each do |pd|
      piece_num = pd[:piece_num]
      points_by_piece[piece_num] ||= []
      points_by_piece[piece_num] += pd[:points]
    end

    # Generate one label per piece
    points_by_piece.each do |piece_num, points|
      # Find the center point of this piece using centroid (average of all points)
      # This works well for wrap-around pieces and curved pieces alike
      sum_x = points.sum { |pt| pt[0] }
      sum_y = points.sum { |pt| pt[1] }
      label_x = sum_x / points.length
      label_y = sum_y / points.length

      # Text with white outline/stroke behind it for readability
      piece_labels << %(<text x="#{label_x.round(2)}" y="#{label_y.round(2)}" fill="white" stroke="white" stroke-width="#{label_stroke_width_in}" font-size="#{label_font_size_in}" font-family="Arial, sans-serif" font-weight="900" text-anchor="middle" dominant-baseline="middle">#{piece_num}</text>)
      piece_labels << %(<text x="#{label_x.round(2)}" y="#{label_y.round(2)}" fill="#{label_color}" font-size="#{label_font_size_in}" font-family="Arial, sans-serif" font-weight="900" text-anchor="middle" dominant-baseline="middle">#{piece_num}</text>)
    end

    label_group = %(<g id="piece-labels">\n#{piece_labels.join("\n")}\n</g>)

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

    # Turn markers group (no longer used, kept for SVG structure compatibility)
    turn_markers_group = ""

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

    # Store piece_data for use by PieceLayoutGenerator
    @piece_data_for_layout = piece_data
    piece_data
  end

  # Return piece_data for use by PieceLayoutGenerator
  attr_reader :piece_data_for_layout

  def generate_with_pieces
    generate
    @piece_data_for_layout
  end
end

#===============================================================================
# PIECE LAYOUT GENERATOR
#===============================================================================
# Generates a layout SVG with all pieces arranged for CNC cutting

class PieceLayoutGenerator
  LAYOUT_PADDING = 0.8        # Padding around each piece (inches)
  LABEL_OFFSET = 0.4          # Offset for label from piece edge (inches)
  CALIBRATION_SIZE = 1.0      # Size of calibration block (inches)

  def initialize(piece_data, inner_width, sidewall_thickness)
    @piece_data = piece_data
    @inner_width = inner_width
    @sidewall_thickness = sidewall_thickness
    @total_width = inner_width + (sidewall_thickness * 2)
  end

  def generate
    return if @piece_data.empty?

    puts ""
    puts "="*60
    puts "GENERATING PIECE LAYOUT"
    puts "="*60

    # Calculate bounds for each piece, rotate to vertical, and normalize to origin
    normalized_pieces = []
    inventory = []

    @piece_data.each do |pd|
      points = pd[:points]
      next if points.nil? || points.length < 2

      # Calculate the principal direction of the piece (start to end)
      start_pt = points.first
      end_pt = points.last
      dx = end_pt[0] - start_pt[0]
      dy = end_pt[1] - start_pt[1]

      # Calculate rotation angle to make the piece vertical (add 90 degrees)
      angle = Math.atan2(dy, dx)
      vertical_angle = -angle + Math::PI / 2  # Rotate to vertical

      # Rotate all centerline points to be vertical
      rotated_centerline = points.map { |p| rotate_point(p, vertical_angle, start_pt) }

      # Build both inner channel and sidewall shapes from rotated centerline
      shapes = build_all_shapes(rotated_centerline)
      next unless shapes

      # Calculate bounding box from outer shape (sidewalls define the full extent)
      all_wall_pts = shapes[:left_wall] + shapes[:right_wall]
      min_x = all_wall_pts.map { |p| p[0] }.min
      max_x = all_wall_pts.map { |p| p[0] }.max
      min_y = all_wall_pts.map { |p| p[1] }.min
      max_y = all_wall_pts.map { |p| p[1] }.max

      width = max_x - min_x
      height = max_y - min_y

      # Normalize all shapes to origin (0,0)
      inner_channel_normalized = shapes[:inner_channel].map { |p| [p[0] - min_x, p[1] - min_y] }
      left_wall_normalized = shapes[:left_wall].map { |p| [p[0] - min_x, p[1] - min_y] }
      right_wall_normalized = shapes[:right_wall].map { |p| [p[0] - min_x, p[1] - min_y] }

      # Calculate arc length (actual track length)
      arc_length = 0.0
      (1...points.length).each do |i|
        adx = points[i][0] - points[i-1][0]
        ady = points[i][1] - points[i-1][1]
        arc_length += Math.sqrt(adx*adx + ady*ady)
      end

      # Calculate straightness (ratio of direct distance to arc length)
      direct_dist = Math.sqrt(dx*dx + dy*dy)
      straightness = arc_length > 0 ? direct_dist / arc_length : 0

      normalized_pieces << {
        piece_num: pd[:piece_num],
        width: width,
        height: height,
        arc_length: arc_length,
        straightness: straightness,
        inner_channel: inner_channel_normalized,
        left_wall: left_wall_normalized,
        right_wall: right_wall_normalized
      }

      inventory << {
        piece_num: pd[:piece_num],
        width: width,
        height: height,
        arc_length: arc_length,
        straightness: straightness
      }
    end

    # Sort pieces: straight pieces first (by straightness desc), then by piece number
    normalized_pieces.sort_by! { |p| [-p[:straightness], p[:piece_num]] }
    inventory.sort_by! { |p| p[:piece_num] }

    # Print inventory
    puts ""
    puts "PIECE INVENTORY:"
    puts "  Track width: #{@inner_width}\" channel + #{@sidewall_thickness}\" sidewalls x2 = #{@total_width}\" total"
    puts "-" * 60
    puts "  #   | Bounding Box     | Track Length | Straightness"
    puts "-" * 60
    total_length = 0.0
    inventory.each do |item|
      total_length += item[:arc_length]
      straight_pct = (item[:straightness] * 100).round(0)
      puts "  #{item[:piece_num].to_s.rjust(2)}  | #{item[:width].round(2).to_s.rjust(6)}\" x #{item[:height].round(2).to_s.ljust(6)}\" | #{item[:arc_length].round(2).to_s.rjust(6)}\"    | #{straight_pct}%"
    end
    puts "-" * 60
    puts "  Total track length: #{total_length.round(2)}\""
    puts ""

    # Layout pieces in rows, packing by height
    layout = calculate_layout(normalized_pieces)
    svg_content = generate_svg(layout, normalized_pieces)

    File.write(PIECES_FILE, svg_content)
    puts "Generated #{PIECES_FILE} with #{normalized_pieces.length} pieces"
  end

  def rotate_point(point, angle, origin)
    cos_a = Math.cos(angle)
    sin_a = Math.sin(angle)
    dx = point[0] - origin[0]
    dy = point[1] - origin[1]
    [
      origin[0] + dx * cos_a - dy * sin_a,
      origin[1] + dx * sin_a + dy * cos_a
    ]
  end

  private

  # Build all shapes for a piece: inner channel and two sidewalls
  # Returns: { inner_channel: [...], left_wall: [...], right_wall: [...] }
  def build_all_shapes(points)
    return nil if points.nil? || points.length < 2

    half_total = @total_width / 2.0
    half_inner = @inner_width / 2.0

    # Four edge lines: outer left, inner left, inner right, outer right
    outer_left = []
    inner_left = []
    inner_right = []
    outer_right = []

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
      inner_left << [pt[0] + norm_x * half_inner, pt[1] + norm_y * half_inner]
      inner_right << [pt[0] - norm_x * half_inner, pt[1] - norm_y * half_inner]
      outer_right << [pt[0] - norm_x * half_total, pt[1] - norm_y * half_total]
    end

    return nil if outer_left.length < 2

    # Inner channel: the area where the car runs (between inner edges)
    inner_channel = inner_left + inner_right.reverse

    # Left sidewall: between outer_left and inner_left
    left_wall = outer_left + inner_left.reverse

    # Right sidewall: between inner_right and outer_right
    right_wall = outer_right + inner_right.reverse

    { inner_channel: inner_channel, left_wall: left_wall, right_wall: right_wall }
  end

  def calculate_layout(pieces)
    positions = []
    current_x = LAYOUT_PADDING
    current_y = LAYOUT_PADDING + LABEL_OFFSET + 0.5  # Extra space for labels at top
    row_max_x = 0
    max_width = 36  # Max layout width in inches

    pieces.each do |piece|
      piece_width = piece[:width] + LAYOUT_PADDING
      piece_height = piece[:height] + LAYOUT_PADDING

      # Move to next row if this piece would exceed max width
      if current_x + piece_width > max_width && current_x > LAYOUT_PADDING + 1
        current_x = LAYOUT_PADDING
        current_y = row_max_x + LAYOUT_PADDING
      end

      positions << {
        piece_num: piece[:piece_num],
        x: current_x,
        y: current_y,
        width: piece[:width],
        height: piece[:height]
      }

      current_x += piece_width
      row_max_x = [row_max_x, current_y + piece_height].max
    end

    # Calculate total dimensions
    total_width = [positions.map { |p| p[:x] + p[:width] }.max + LAYOUT_PADDING, max_width].min
    total_height = row_max_x + LAYOUT_PADDING

    # Add space for calibration block and notes
    total_height += CALIBRATION_SIZE + LAYOUT_PADDING * 3

    { positions: positions, width: total_width, height: total_height }
  end

  def generate_svg(layout, pieces)
    width = layout[:width].ceil
    height = layout[:height].ceil

    svg = <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <svg xmlns="http://www.w3.org/2000/svg"
           width="#{width}in"
           height="#{height}in"
           viewBox="0 0 #{width} #{height}">
      <style>
        .inner-channel { fill: #AAAAAA; stroke: none; }
        .sidewall { fill: #333333; stroke: none; }
        .label { font-family: Arial, sans-serif; font-weight: bold; fill: #333; }
        .note { font-family: Arial, sans-serif; font-size: 0.2px; fill: #666; }
        .calibration { fill: #333333; stroke: none; }
      </style>
      <rect width="100%" height="100%" fill="white" />
      <defs>
      <pattern id="background-grid" width="1.0" height="1.0" patternUnits="userSpaceOnUse">
      <path d="M 1.0 0 L 0 0 0 1.0" fill="none" stroke="#CCCCCC" stroke-width="0.02"/>
      </pattern>
      </defs>
      <rect x="0" y="0" width="#{width}" height="#{height}" fill="url(#background-grid)"/>
    SVG

    # Add each piece
    layout[:positions].each_with_index do |pos, idx|
      piece = pieces[idx]
      translate_x = pos[:x]
      translate_y = pos[:y]

      # Inner channel (light gray) - where the car runs
      channel_path = polygon_to_path(piece[:inner_channel], translate_x, translate_y)
      svg += %(<path d="#{channel_path}" class="inner-channel" />\n)

      # Left sidewall (black)
      left_wall_path = polygon_to_path(piece[:left_wall], translate_x, translate_y)
      svg += %(<path d="#{left_wall_path}" class="sidewall" />\n)

      # Right sidewall (black)
      right_wall_path = polygon_to_path(piece[:right_wall], translate_x, translate_y)
      svg += %(<path d="#{right_wall_path}" class="sidewall" />\n)

      # Piece label - positioned above the piece
      label_x = translate_x + piece[:width] / 2
      label_y = translate_y - LABEL_OFFSET
      font_size = 0.4

      svg += %(<text x="#{label_x.round(3)}" y="#{label_y.round(3)}" class="label" style="font-size: #{font_size.round(2)}px;" text-anchor="middle" dominant-baseline="middle">#{piece[:piece_num]}</text>\n)
    end

    # Add calibration block at bottom right
    cal_x = width - CALIBRATION_SIZE - LAYOUT_PADDING
    cal_y = height - CALIBRATION_SIZE - LAYOUT_PADDING
    svg += %(<rect x="#{cal_x}" y="#{cal_y}" width="#{CALIBRATION_SIZE}" height="#{CALIBRATION_SIZE}" class="calibration" />\n)
    svg += %(<text x="#{LAYOUT_PADDING}" y="#{height - LAYOUT_PADDING / 2}" class="note">Cut depth: #{SIDEWALL_HEIGHT_IN}\" | Channel width: #{@inner_width}\" | Calibration: #{CALIBRATION_SIZE}\"x#{CALIBRATION_SIZE}\"</text>\n)

    svg += "</svg>\n"
    svg
  end

  def polygon_to_path(points, offset_x = 0, offset_y = 0)
    return "" if points.nil? || points.length < 3

    translated = points.map { |p| [p[0] + offset_x, p[1] + offset_y] }

    commands = ["M #{translated.first[0].round(3)} #{translated.first[1].round(3)}"]
    translated[1..-1].each do |pt|
      commands << "L #{pt[0].round(3)} #{pt[1].round(3)}"
    end
    commands << "Z"
    commands.join(" ")
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
piece_data = visualizer.generate

# Generate piece layout
piece_layout = PieceLayoutGenerator.new(piece_data, INNER_TRACK_WIDTH_IN, SIDEWALL_THICKNESS_IN)
piece_layout.generate

puts ""
print 'Opening in Cursor...'
system("cursor", OUTPUT_FILE) # Keep this comment
# system("cursor", PIECES_FILE) # Keep this comment
# system("cursor", PIECES_LAYED_OUT_FILE)
