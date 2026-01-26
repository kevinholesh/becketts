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

# Track dimensions (inches)
TRACK_WIDTH_IN = 1.6     # Lane width - enough clearance for the car
WALL_HEIGHT_IN = 0.3     # Side wall height to keep cars on track

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

# Track simplification
SIMPLIFY_STRAIGHTS = true         # Combine short straights into longer pieces
SIMPLIFY_THRESHOLD_DEG = 10.0     # Angle threshold for "straight" detection

# Split point configuration
MIN_SPLIT_SPACING = 0.05          # Minimum spacing between splits (as fraction of path)
CURVATURE_THRESHOLD = 0.15        # Threshold for detecting significant curves

# Straight-to-curve splitting
SPLIT_AT_STRAIGHT_END = true      # Split where straights meet curves
STRAIGHT_CURVATURE_MAX = 0.05     # Max curvature to be considered "straight"
MIN_STRAIGHT_LENGTH = 0.08        # Minimum length (as fraction) to qualify as a straight

# Straight piece simplification
STRAIGHTEN_THRESHOLD = 0.015      # Max average curvature to simplify to a straight line

# Chicane protection - keep tight S-curves as single pieces
CHICANE_PROTECTION = true         # Enable chicane detection
CHICANE_ANGLE_THRESHOLD = 60.0    # Degrees - direction change that indicates a chicane
CHICANE_MIN_REVERSALS = 2         # Minimum direction reversals to qualify as chicane

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
  0.259,  # Split 4
  0.285,  # Split 5
  0.457,  # Split 6
  0.575,  # Split 7
  0.605,  # Split 8
  0.745,  # Split 9
  0.805,  # Split 10
  0.89,   # Split 11
]

# Visual settings for split preview (all dimensions in inches)
SPLIT_LINE_COLOR = '#FF0000'
SPLIT_LINE_WIDTH_IN = 0.1         # Thin line for precise split visualization
SVG_PADDING_IN = 5.0              # White border padding around the SVG (inches)

# Ghost track settings - shows original track for comparison
SHOW_GHOST_TRACK = true           # Enable ghost track overlay
GHOST_TRACK_COLOR = '#FF0000'     # Light gray for ghost
GHOST_TRACK_OPACITY = 0.4         # Transparency (0-1)
GHOST_TRACK_STYLE = 'solid'       # 'solid' or 'dashed'

# Tight radius warning visualization
SHOW_TIGHT_RADIUS_WARNINGS = true # Highlight curves that are too tight for cars
TIGHT_RADIUS_THRESHOLD_IN = 1.5   # Warn about radii below this (inches)
TIGHT_RADIUS_COLOR = '#FF00FF'    # Magenta for warnings

# Main track visual style - "railroad" style with two rails and gap
# NOTE: All dimensions below are in INCHES (output SVG uses 1 unit = 1 inch for CNC)
TRACK_OUTER_WIDTH_IN = TRACK_WIDTH_IN  # Use the track width constant (1.6")
TRACK_RAIL_WIDTH_IN = 0.1              # Width of each rail line
TRACK_COLOR = '#000000'                # Color of the rails

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

  def split_points
    # Find points where we should split the track based on direction changes
    splits = []

    # Always split at start
    splits << 0.0

    # Calculate cumulative angle changes to detect significant direction shifts
    # We look for points where the direction has changed significantly
    angle_threshold = SIMPLIFY_THRESHOLD_DEG * Math::PI / 180.0  # Convert to radians

    # Method 1: Track cumulative direction changes
    cumulative_angle = 0.0
    last_split_index = 0

    (1...@tangents.length).each do |i|
      prev_t = @tangents[i-1]
      curr_t = @tangents[i]

      # Calculate angle between consecutive tangents
      dot = prev_t[0] * curr_t[0] + prev_t[1] * curr_t[1]
      dot = [[dot, -1.0].max, 1.0].min  # Clamp for numerical stability
      angle = Math.acos(dot)

      # Determine direction (left or right turn) using cross product
      cross = prev_t[0] * curr_t[1] - prev_t[1] * curr_t[0]
      signed_angle = cross >= 0 ? angle : -angle

      cumulative_angle += signed_angle

      # Check if we should split here
      t_value = i.to_f / @tangents.length

      # Split conditions:
      # 1. Significant cumulative angle since last split (corner completed)
      # 2. Direction reversal (turn the other way)
      # 3. Minimum spacing respected
      if (t_value - splits.last) >= MIN_SPLIT_SPACING
        if cumulative_angle.abs > angle_threshold * 3  # ~45 degrees accumulated
          splits << t_value
          cumulative_angle = 0.0
          last_split_index = i
        end
      end
    end

    # Method 2: Also split at local curvature extrema (apex of corners)
    window = 20
    smoothed_curvatures = smooth_curvatures(window)

    i = window
    while i < smoothed_curvatures.length - window
      curv = smoothed_curvatures[i]

      # Check if this is a local maximum
      is_local_max = true
      (-window..window).each do |offset|
        next if offset == 0
        if smoothed_curvatures[i + offset] > curv
          is_local_max = false
          break
        end
      end

      if is_local_max && curv > CURVATURE_THRESHOLD * 0.5
        t_value = i.to_f / smoothed_curvatures.length

        # Only add if sufficiently spaced from existing splits
        closest_split = splits.min_by { |s| (s - t_value).abs }
        if (t_value - closest_split).abs >= MIN_SPLIT_SPACING * 0.7
          splits << t_value
        end
      end

      i += 1
    end

    # Sort and ensure end point
    splits = splits.sort.uniq
    splits << 1.0 unless splits.last && splits.last > 0.95

    # Merge splits that are too close together
    merged = [splits.first]
    splits[1..-1].each do |s|
      if (s - merged.last) >= MIN_SPLIT_SPACING * 0.5
        merged << s
      end
    end

    # Add splits at straight-to-curve transitions
    if SPLIT_AT_STRAIGHT_END
      merged = add_straight_curve_splits(merged)
    end

    # Apply chicane protection
    if CHICANE_PROTECTION
      merged = apply_chicane_protection(merged)
    end

    merged
  end

  def add_straight_curve_splits(splits)
    # Find straight sections and add splits at their ends (where curves begin)
    window = 10
    smoothed = smooth_curvatures(window)

    straight_transitions = []

    # Scan through the track looking for straight-to-curve transitions
    in_straight = false
    straight_start = 0

    smoothed.each_with_index do |curv, i|
      t_value = i.to_f / smoothed.length
      is_straight = curv < STRAIGHT_CURVATURE_MAX

      if is_straight && !in_straight
        # Starting a straight section
        in_straight = true
        straight_start = t_value
      elsif !is_straight && in_straight
        # Ending a straight section - this is where we want to split
        straight_length = t_value - straight_start
        if straight_length >= MIN_STRAIGHT_LENGTH
          # Add split at the end of the straight (beginning of curve)
          straight_transitions << { t: t_value, type: :straight_end }
        end
        in_straight = false
      end
    end

    # Also detect curve-to-straight transitions (beginning of straights)
    in_curve = false
    curve_start = 0
    smoothed.each_with_index do |curv, i|
      t_value = i.to_f / smoothed.length
      is_curve = curv >= STRAIGHT_CURVATURE_MAX * 2

      if is_curve && !in_curve
        in_curve = true
        curve_start = t_value
      elsif !is_curve && in_curve
        # Exiting a curve into a straight
        # Look ahead to confirm this is actually a straight
        look_ahead = [i + 20, smoothed.length - 1].min
        upcoming_avg = smoothed[i..look_ahead].sum / (look_ahead - i + 1).to_f
        if upcoming_avg < STRAIGHT_CURVATURE_MAX
          straight_transitions << { t: t_value, type: :straight_start }
        end
        in_curve = false
      end
    end

    # Merge new splits with existing ones
    new_splits = straight_transitions.map { |st| st[:t] }
    all_splits = (splits + new_splits).sort.uniq

    # Remove duplicates that are too close
    merged = [all_splits.first]
    all_splits[1..-1].each do |s|
      if (s - merged.last) >= MIN_SPLIT_SPACING * 0.4
        merged << s
      end
    end

    merged
  end

  def apply_chicane_protection(splits)
    return splits if splits.length < 3

    # Detect chicanes by looking for rapid direction reversals
    chicane_threshold = CHICANE_ANGLE_THRESHOLD * Math::PI / 180.0

    protected_ranges = []

    # Analyze direction changes between split points
    (0...splits.length - 1).each do |i|
      t_start = splits[i]
      t_end = splits[[i + 1, splits.length - 1].min]

      # Sample direction changes within this segment
      reversals = count_direction_reversals(t_start, t_end, chicane_threshold)

      if reversals >= CHICANE_MIN_REVERSALS
        # This segment contains a chicane - find its extent
        # Look ahead to see if the chicane continues
        chicane_end = t_end

        j = i + 1
        while j < splits.length - 1
          next_reversals = count_direction_reversals(splits[j], splits[j + 1], chicane_threshold)
          if next_reversals >= 1
            chicane_end = splits[j + 1]
            j += 1
          else
            break
          end
        end

        protected_ranges << { start: t_start, finish: chicane_end }
      end
    end

    # Merge overlapping protected ranges
    merged_ranges = merge_ranges(protected_ranges)

    # Remove splits that fall within chicane ranges (except boundaries)
    result = []
    splits.each do |s|
      in_chicane = merged_ranges.any? do |range|
        s > range[:start] && s < range[:finish]
      end

      unless in_chicane
        result << s
      end
    end

    # Ensure chicane boundaries are included
    merged_ranges.each do |range|
      result << range[:start] unless result.include?(range[:start])
      result << range[:finish] unless result.include?(range[:finish])
    end

    result.sort.uniq
  end

  def count_direction_reversals(t_start, t_end, threshold)
    start_idx = (t_start * (@tangents.length - 1)).round
    end_idx = (t_end * (@tangents.length - 1)).round

    return 0 if end_idx <= start_idx

    reversals = 0
    cumulative = 0.0
    last_sign = nil

    (start_idx...end_idx).each do |i|
      next if i >= @tangents.length - 1

      prev_t = @tangents[i]
      curr_t = @tangents[i + 1]

      dot = prev_t[0] * curr_t[0] + prev_t[1] * curr_t[1]
      dot = [[dot, -1.0].max, 1.0].min
      angle = Math.acos(dot)

      cross = prev_t[0] * curr_t[1] - prev_t[1] * curr_t[0]
      sign = cross >= 0 ? 1 : -1

      cumulative += angle

      if cumulative > threshold
        if last_sign && sign != last_sign
          reversals += 1
        end
        last_sign = sign
        cumulative = 0.0
      end
    end

    reversals
  end

  def merge_ranges(ranges)
    return [] if ranges.empty?

    sorted = ranges.sort_by { |r| r[:start] }
    merged = [sorted.first.dup]

    sorted[1..-1].each do |range|
      if range[:start] <= merged.last[:finish]
        merged.last[:finish] = [merged.last[:finish], range[:finish]].max
      else
        merged << range.dup
      end
    end

    merged
  end

  def smooth_curvatures(window)
    result = []
    @curvatures.each_with_index do |_, i|
      start_i = [i - window, 0].max
      end_i = [i + window, @curvatures.length - 1].min
      avg = @curvatures[start_i..end_i].sum / (end_i - start_i + 1).to_f
      result << avg
    end
    result
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
    # Create a polygon from the piece points (track centerline expanded to track width)
    clip_path_id = "grain-clip-#{(t_start * 1000).round}-#{(t_end * 1000).round}"

    # Build clip path from piece points expanded to exact track width
    half_width = TRACK_OUTER_WIDTH_IN / 2.0

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
  def build_modified_path(analyzer, splits, original_path_data)
    # Get all t-values where we need to check for straightening
    # These are the boundaries between pieces
    all_t_values = splits.dup.sort

    # Ensure we have 0.0 and 1.0
    all_t_values.unshift(0.0) unless all_t_values.first == 0.0
    all_t_values.push(1.0) unless all_t_values.last == 1.0
    all_t_values = all_t_values.sort.uniq

    # Build the path by going through each segment
    path_commands = []
    first_point = analyzer.point_at(0.0)
    path_commands << "M #{first_point[0].round(3)} #{first_point[1].round(3)}"

    straightened_pieces = []

    (0...all_t_values.length - 1).each do |i|
      t_start = all_t_values[i]
      t_end = all_t_values[i + 1]

      is_straight = analyzer.is_piece_straight?(t_start, t_end)

      if is_straight
        # Just draw a straight line to the end point
        end_point = analyzer.point_at(t_end)
        path_commands << "L #{end_point[0].round(3)} #{end_point[1].round(3)}"
        straightened_pieces << [t_start, t_end]
      else
        # Use the original curve points as a polyline
        piece_pts = analyzer.piece_points(t_start, t_end)

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
      straightened_pieces.each do |t_start, t_end|
        puts "  t=#{t_start.round(3)} to #{t_end.round(3)} -> straightened"
      end
    end

    path_commands.join(" ")
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

    # Generate split lines with numbered labels
    split_lines = []
    split_labels = []
    label_font_size_in = 0.5
    label_stroke_width_in = 0.15

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

      # Add numbered label centered on the split line with white background
      label_x = point[0]
      label_y = point[1]

      # Text with white outline/stroke behind it for readability
      split_labels << %(<text x="#{label_x.round(2)}" y="#{label_y.round(2)}" fill="white" stroke="white" stroke-width="#{label_stroke_width_in}" font-size="#{label_font_size_in}" font-family="Arial, sans-serif" font-weight="bold" text-anchor="middle" dominant-baseline="middle">#{split_num}</text>)
      split_labels << %(<text x="#{label_x.round(2)}" y="#{label_y.round(2)}" fill="#{SPLIT_LINE_COLOR}" font-size="#{label_font_size_in}" font-family="Arial, sans-serif" font-weight="bold" text-anchor="middle" dominant-baseline="middle">#{split_num}</text>)

      puts "  Split #{split_num}: t=#{t.round(3)} at (#{point[0].round(1)}, #{point[1].round(1)})"
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

    # Find and visualize tight radius sections
    tight_warnings = []
    if SHOW_TIGHT_RADIUS_WARNINGS
      tight_sections = analyzer.find_tight_radius_sections(TIGHT_RADIUS_THRESHOLD_IN)

      if tight_sections.any?
        puts ""
        puts "TIGHT RADIUS WARNINGS (< #{TIGHT_RADIUS_THRESHOLD_IN}\" min radius):"
        tight_sections.each_with_index do |section, i|
          pt = section[:center_point]
          puts "  ##{i+1}: t=#{section[:t_start].round(3)}-#{section[:t_end].round(3)}, radius=#{section[:min_radius].round(2)}\" at (#{pt[0].round(1)}, #{pt[1].round(1)})"

          # Create warning circle marker
          marker_r = 0.8
          tight_warnings << %(<circle cx="#{pt[0].round(2)}" cy="#{pt[1].round(2)}" r="#{marker_r}" fill="none" stroke="#{TIGHT_RADIUS_COLOR}" stroke-width="0.1"/>)
          tight_warnings << %(<text x="#{pt[0].round(2)}" y="#{(pt[1] - marker_r - 0.2).round(2)}" fill="#{TIGHT_RADIUS_COLOR}" font-size="0.5" font-family="Arial" text-anchor="middle">#{section[:min_radius].round(1)}"</text>)
        end
        puts ""
        puts "  These sections need to be widened in the source SVG."
      else
        puts ""
        puts "All turn radii OK (>= #{TIGHT_RADIUS_THRESHOLD_IN}\")"
      end
    end

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
    viewbox_x = track_min_x - SVG_PADDING_IN
    viewbox_y = track_min_y - SVG_PADDING_IN
    viewbox_width = (track_max_x - track_min_x) + SVG_PADDING_IN * 2 + dim_margin_in
    viewbox_height = (track_max_y - track_min_y) + SVG_PADDING_IN * 2 + dim_margin_in

    padded_viewbox = [viewbox_x, viewbox_y, viewbox_width, viewbox_height].map { |v| v.round(4) }.join(' ')

    # SVG pixel dimensions (1:1 with viewbox units)
    padded_width = viewbox_width
    padded_height = viewbox_height

    # Build modified SVG with padding
    # Create a background rect that covers the viewbox area
    bg_rect = %(<rect x="#{viewbox_x}" y="#{viewbox_y}" width="#{viewbox_width}" height="#{viewbox_height}" fill="white"/>)
    split_group = %(<g id="split-lines">\n#{split_lines.join("\n")}\n</g>)
    label_group = %(<g id="split-labels">\n#{split_labels.join("\n")}\n</g>)

    # Create ghost track if enabled - shows ORIGINAL track layout scaled to match output
    # This lets you compare the original curves vs simplified output at the same size
    ghost_track = ""
    if SHOW_GHOST_TRACK
      ghost_style = GHOST_TRACK_STYLE == 'dashed' ? 'stroke-dasharray="10,5"' : ''

      ghost_stroke_width_in = 0.1

      if SCALING_MODE != :none && analyzer.scale_factor != 1.0
        # The scaled track's center = original track's center (scaling preserves center)
        # Use the track bounds already calculated above
        center_x = (track_min_x + track_max_x) / 2.0
        center_y = (track_min_y + track_max_y) / 2.0

        scale = analyzer.scale_factor
        # Transform: move to origin, scale, move back to center
        # Since scaling preserves the center, we use the same center for both translates
        ghost_track = %(<g id="ghost-track" opacity="#{GHOST_TRACK_OPACITY}" transform="translate(#{center_x}, #{center_y}) scale(#{scale}) translate(#{-center_x}, #{-center_y})">
<path d="#{path_data}" stroke="#{GHOST_TRACK_COLOR}" stroke-width="#{ghost_stroke_width_in / scale}" fill="none" #{ghost_style}/>
</g>)
      else
        ghost_track = %(<g id="ghost-track" opacity="#{GHOST_TRACK_OPACITY}">
<path d="#{path_data}" stroke="#{GHOST_TRACK_COLOR}" stroke-width="#{ghost_stroke_width_in}" fill="none" #{ghost_style}/>
</g>)
      end
    end

    # Create railroad-style main track with truly transparent gap using SVG mask
    inner_gap_width = TRACK_OUTER_WIDTH_IN - (TRACK_RAIL_WIDTH_IN * 2)

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
    modified_path_data = build_modified_path(analyzer, splits, path_data)

    main_track = %(<defs>
<mask id="railroad-mask">
<path d="#{modified_path_data}" stroke="white" stroke-width="#{TRACK_OUTER_WIDTH_IN}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
<path d="#{modified_path_data}" stroke="black" stroke-width="#{inner_gap_width}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
</mask>
#{grain_clip_paths.join("\n")}
</defs>
<g id="main-track">
<path d="#{modified_path_data}" stroke="#{TRACK_COLOR}" stroke-width="#{TRACK_OUTER_WIDTH_IN}" stroke-linecap="round" stroke-linejoin="round" fill="none" mask="url(#railroad-mask)"/>
</g>)

    # Create grain direction group - uses per-piece polygon clip paths
    grain_group = ""
    if grain_groups.any?
      grain_group = %(<g id="grain-direction">\n#{grain_groups.join("\n")}\n</g>)
    end

    # Create scale bar in lower left corner
    scale_bar = ""
    if SHOW_SCALE_BAR
      scale_length = 12.0  # 12 inches (1 foot) - output is in inches so 1 unit = 1 inch
      margin_in = 1.5

      # Position in lower left of padded viewbox
      bar_x = viewbox_x + margin_in
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

      width_label = format_feet_inches(width_inches)
      height_label = format_feet_inches(height_inches)

      dim_color = SCALE_BAR_COLOR
      dim_offset_in = 2.0   # Distance from track edge (inches)
      tick_size_in = 0.5    # Tick mark size (inches)
      stroke_width_in = 0.05
      font_size_in = 0.8

      # Width dimension (below track)
      w_y = track_max_y + dim_offset_in
      # Height dimension (right of track)
      h_x = track_max_x + dim_offset_in

      dimension_lines = %(<g id="dimensions" fill="#{dim_color}" stroke="#{dim_color}" stroke-width="#{stroke_width_in}">
<!-- Width dimension -->
<line x1="#{track_min_x}" y1="#{w_y}" x2="#{track_max_x}" y2="#{w_y}"/>
<line x1="#{track_min_x}" y1="#{w_y - tick_size_in/2}" x2="#{track_min_x}" y2="#{w_y + tick_size_in/2}"/>
<line x1="#{track_max_x}" y1="#{w_y - tick_size_in/2}" x2="#{track_max_x}" y2="#{w_y + tick_size_in/2}"/>
<text x="#{(track_min_x + track_max_x) / 2}" y="#{w_y + 1.0}" font-size="#{font_size_in}" font-family="Arial, sans-serif" text-anchor="middle" stroke="none">#{width_label}</text>
<!-- Height dimension -->
<line x1="#{h_x}" y1="#{track_min_y}" x2="#{h_x}" y2="#{track_max_y}"/>
<line x1="#{h_x - tick_size_in/2}" y1="#{track_min_y}" x2="#{h_x + tick_size_in/2}" y2="#{track_min_y}"/>
<line x1="#{h_x - tick_size_in/2}" y1="#{track_max_y}" x2="#{h_x + tick_size_in/2}" y2="#{track_max_y}"/>
<text x="#{h_x + 0.5}" y="#{(track_min_y + track_max_y) / 2}" font-size="#{font_size_in}" font-family="Arial, sans-serif" text-anchor="start" dominant-baseline="middle" stroke="none">#{height_label}</text>
</g>)
    end

    # Update SVG dimensions and viewBox
    modified_svg = svg_content.dup
    modified_svg = modified_svg.sub(/width="[^"]+"/, %(width="#{padded_width.round(2)}"))
    modified_svg = modified_svg.sub(/height="[^"]+"/, %(height="#{padded_height.round(2)}"))
    modified_svg = modified_svg.sub(/viewBox="[^"]+"/, %(viewBox="#{padded_viewbox}"))

    # Remove the original path element - we'll replace it with our styled tracks
    modified_svg = modified_svg.sub(/<path[^>]+\/>/, '')

    # Build content: background, ghost track, main track
    insert_content = "#{bg_rect}\n#{ghost_track}\n#{main_track}"

    # Insert after opening <svg ...> tag (find the svg tag and insert after it)
    modified_svg = modified_svg.sub(/(<svg[^>]*>)/, "\\1\n#{insert_content}\n")

    # Build tight radius warnings group
    warnings_group = ""
    if tight_warnings.any?
      warnings_group = %(<g id="tight-radius-warnings">\n#{tight_warnings.join("\n")}\n</g>)
    end

    # Build test cars group
    test_cars_group = ""
    if test_car_elements.any?
      test_cars_group = %(<g id="test-cars">\n#{test_car_elements.join("\n")}\n</g>)
    end

    # Insert grain direction, split lines, labels, scale bar, warnings, and test cars before closing </svg>
    modified_svg = modified_svg.sub(/<\/svg>/, "#{grain_group}\n#{split_group}\n#{label_group}\n#{test_cars_group}\n#{scale_bar}\n#{dimension_lines}\n#{warnings_group}\n</svg>")

    File.write(@output_file, modified_svg)

    puts ""
    puts "Generated #{@output_file} with #{splits.length} split indicators"
    puts ""
    puts "Piece count estimate: #{splits.length - 1} pieces"
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
