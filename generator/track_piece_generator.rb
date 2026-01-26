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

# Hot Wheels Premium F1 car dimensions (in mm)
CAR_LENGTH_MM = 76.0      # ~3 inches
CAR_WIDTH_MM = 32.0       # ~1.25 inches
CAR_HEIGHT_MM = 20.0      # ~0.8 inches

# Track dimensions (in mm)
TRACK_WIDTH_MM = 60.0     # Lane width - enough clearance for the car
WALL_HEIGHT_MM = 10.0     # Side wall height to keep cars on track

# Turning constraints (in mm)
# Minimum radius should be at least 1.5x car length for smooth turns
MIN_TURN_RADIUS_MM = 120.0        # Tight chicane minimum
COMFORTABLE_TURN_RADIUS_MM = 180.0 # Comfortable cornering

# Maximum assembled track size (in mm)
MAX_TRACK_DIMENSION_MM = 1524.0   # 5 feet = 60 inches = 1524mm

# Wood/CNC constraints (in mm)
MAX_PIECE_LENGTH_MM = 300.0       # Max length of a single piece (for wood grain)
MIN_PIECE_LENGTH_MM = 100.0       # Min length to be practical
WOOD_THICKNESS_MM = 19.0          # 3/4 inch walnut

# Track simplification
SIMPLIFY_STRAIGHTS = true         # Combine short straights into longer pieces
SIMPLIFY_THRESHOLD_DEG = 10.0     # Angle threshold for "straight" detection

# Split point configuration
MIN_SPLIT_SPACING = 0.05          # Minimum spacing between splits (as fraction of path)
CURVATURE_THRESHOLD = 0.15        # Threshold for detecting significant curves

# Straight-to-curve splitting
SPLIT_AT_STRAIGHT_END = true      # Split where straights meet curves
STRAIGHT_CURVATURE_MAX = 0.02     # Max curvature to be considered "straight"
MIN_STRAIGHT_LENGTH = 0.03        # Minimum length (as fraction) to qualify as a straight

# Chicane protection - keep tight S-curves as single pieces
CHICANE_PROTECTION = true         # Enable chicane detection
CHICANE_ANGLE_THRESHOLD = 60.0    # Degrees - direction change that indicates a chicane
CHICANE_MIN_REVERSALS = 2         # Minimum direction reversals to qualify as chicane

#===============================================================================
# TRACK DIRECTION AND START/FINISH
#===============================================================================
# Set the start/finish line and racing direction

# t-value where split 1 (start/finish) should be located
# Set to the t-value closest to where you want numbering to begin
START_FINISH_T = 0.524    # Near current split 11

# Reverse the direction of numbering (true = clockwise on track)
REVERSE_DIRECTION = true

#===============================================================================
# MANUAL SPLIT ADJUSTMENTS
#===============================================================================
# These let you tweak individual splits while keeping auto-generated ones.
# Use the split numbers shown in the SVG output.

# Move a split to a new position (split_number => new_t_value)
# Example: { 5 => 0.25 } moves split 5 to t=0.25
MOVE_SPLITS = {
  2 => 0.05,
  # 12 => 0.70,
}

# Remove specific splits by number (they won't appear)
# Example: [3, 8] removes splits 3 and 8
REMOVE_SPLITS = [
  # 20,  # Merge with split 1 (same location on closed loop)
]

# Add new splits at these t-values (0.0 to 1.0)
# These will be inserted and numbered accordingly
ADD_SPLITS = [
  # 0.15,
  # 0.85,
]

# Visual settings for split preview
SPLIT_LINE_COLOR = '#FF0000'
SPLIT_LINE_WIDTH = 2.0
SPLIT_LINE_LENGTH = 30.0          # Length of split indicator lines
SVG_PADDING = 40.0                # White border padding around the SVG

# Ghost track settings - shows original track for comparison
SHOW_GHOST_TRACK = true           # Enable ghost track overlay
GHOST_TRACK_COLOR = '#FF0000'     # Light gray for ghost
GHOST_TRACK_OPACITY = 0.5         # Transparency (0-1)
GHOST_TRACK_STYLE = 'solid'       # 'solid' or 'dashed'

# Main track visual style - "railroad" style with two rails and gap
TRACK_OUTER_WIDTH = 12.0          # Total width of the track (outer edges)
TRACK_RAIL_WIDTH = 2.5            # Width of each rail line
TRACK_COLOR = '#000000'           # Color of the rails

# Grain direction visualization
SHOW_GRAIN_DIRECTION = true       # Show optimal grain direction for each piece
GRAIN_LINE_COLOR = '#5D3A1A'      # Dark brown for wood grain
GRAIN_LINE_OPACITY = 0.7          # Darker opacity for grain lines
GRAIN_LINE_SPACING = 3.0          # Spacing between grain lines (in SVG units)
GRAIN_LINE_WIDTH = 0.8            # Width of grain lines

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
# TRACK ANALYZER
#===============================================================================

class TrackAnalyzer
  attr_reader :points, :curvatures, :path_length

  def initialize(path_data, samples_per_curve: 50)
    @path_data = path_data
    @samples_per_curve = samples_per_curve
    @points = []
    @curvatures = []
    @tangents = []
    analyze
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
    num_lines = (diagonal / GRAIN_LINE_SPACING).ceil + 2

    # Generate parallel lines along the grain direction
    (-num_lines..num_lines).each do |i|
      # Offset from center along perpendicular direction
      offset = i * GRAIN_LINE_SPACING

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

    # Build clip path from piece points expanded to track width
    half_width = TRACK_OUTER_WIDTH / 2.0 + 2  # Slightly wider to ensure coverage

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
      svg += %(<line x1="#{line[0].round(2)}" y1="#{line[1].round(2)}" x2="#{line[2].round(2)}" y2="#{line[3].round(2)}" stroke="#{GRAIN_LINE_COLOR}" stroke-width="#{GRAIN_LINE_WIDTH}"/>\n)
    end
    svg += %(</g>\n)

    svg
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

    # Start with auto-generated splits
    splits = analyzer.split_points
    puts "Auto-generated #{splits.length} splits"

    # Apply manual adjustments
    adjustments_made = []

    # 1. Remove specified splits (by original number, 1-indexed)
    if REMOVE_SPLITS.any?
      # Remove in reverse order so indices stay valid
      REMOVE_SPLITS.sort.reverse.each do |split_num|
        idx = split_num - 1
        if idx >= 0 && idx < splits.length
          removed_t = splits.delete_at(idx)
          adjustments_made << "Removed split #{split_num} (was t=#{removed_t.round(3)})"
        end
      end
    end

    # 2. Move specified splits (by original number, 1-indexed)
    # Note: This uses original numbering before removes
    if MOVE_SPLITS.any?
      # We need to track original indices, so rebuild from auto-generated
      original_splits = analyzer.split_points
      MOVE_SPLITS.each do |split_num, new_t|
        idx = split_num - 1
        if idx >= 0 && idx < original_splits.length
          old_t = original_splits[idx]
          # Find and update in current splits array
          current_idx = splits.index { |s| (s - old_t).abs < 0.001 }
          if current_idx
            splits[current_idx] = new_t
            adjustments_made << "Moved split #{split_num}: t=#{old_t.round(3)} -> t=#{new_t.round(3)}"
          end
        end
      end
    end

    # 3. Add new splits
    if ADD_SPLITS.any?
      ADD_SPLITS.each do |new_t|
        splits << new_t
        adjustments_made << "Added new split at t=#{new_t.round(3)}"
      end
    end

    # Re-sort and remove duplicates
    splits = splits.sort.uniq

    if adjustments_made.any?
      puts ""
      puts "Manual adjustments applied:"
      adjustments_made.each { |a| puts "  #{a}" }
    end

    # Reorder splits based on start/finish position and direction
    # Find the split closest to START_FINISH_T
    start_idx = splits.each_with_index.min_by { |t, _| (t - START_FINISH_T).abs }[1]

    # Rotate array so start/finish is first
    splits = splits.rotate(start_idx)

    # Reverse direction if needed
    if REVERSE_DIRECTION
      # Keep first element (start/finish), reverse the rest
      first = splits.shift
      splits = [first] + splits.reverse
    end

    puts ""
    puts "Track direction: #{REVERSE_DIRECTION ? 'REVERSED' : 'NORMAL'}"
    puts "Start/finish at t=#{splits.first.round(3)}"

    puts ""
    puts "Track Analysis:"
    puts "  Total points sampled: #{analyzer.points.length}"
    puts "  Approximate path length: #{analyzer.path_length.round(2)} SVG units"
    puts "  Split points found: #{splits.length}"
    puts ""

    # Generate split lines with numbered labels
    split_lines = []
    split_labels = []
    splits.each_with_index do |t, i|
      split_num = i + 1
      point = analyzer.point_at(t)
      tangent = analyzer.tangent_at(t)

      # Perpendicular to tangent
      perp = [-tangent[1], tangent[0]]

      # Create a line perpendicular to the track at this point
      half_len = SPLIT_LINE_LENGTH / 2
      x1 = point[0] - perp[0] * half_len
      y1 = point[1] - perp[1] * half_len
      x2 = point[0] + perp[0] * half_len
      y2 = point[1] + perp[1] * half_len

      split_lines << %(<line x1="#{x1.round(3)}" y1="#{y1.round(3)}" x2="#{x2.round(3)}" y2="#{y2.round(3)}" stroke="#{SPLIT_LINE_COLOR}" stroke-width="#{SPLIT_LINE_WIDTH}"/>)

      # Add numbered label offset from the split line
      label_offset = half_len + 12  # Position label beyond the split line
      label_x = point[0] + perp[0] * label_offset
      label_y = point[1] + perp[1] * label_offset

      # Calculate display coordinate (0.0 at split 1, increasing in racing direction)
      start_t = splits[0]
      if REVERSE_DIRECTION
        # In reverse, distance increases as t decreases (with wrap-around)
        if t <= start_t
          display_t = start_t - t
        else
          display_t = start_t + (1.0 - t)
        end
      else
        # In forward, distance increases as t increases (with wrap-around)
        if t >= start_t
          display_t = t - start_t
        else
          display_t = (1.0 - start_t) + t
        end
      end

      # Format: "6 (0.25)" with bold number, non-bold parenthesis
      split_labels << %(<text x="#{label_x.round(2)}" y="#{label_y.round(2)}" fill="#{SPLIT_LINE_COLOR}" font-size="8" font-family="Arial, sans-serif" text-anchor="middle" dominant-baseline="middle"><tspan font-weight="bold">#{split_num}</tspan> <tspan font-weight="normal">(#{display_t.round(2)})</tspan></text>)

      puts "  Split #{split_num}: t=#{t.round(3)} at (#{point[0].round(1)}, #{point[1].round(1)})"
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
        # In reverse mode, piece goes from t1 backwards to t2
        # We need to figure out which segment of the track this represents

        if REVERSE_DIRECTION
          if t1 > t2
            # Normal case in reverse: t1=0.5, t2=0.4 means segment from 0.4 to 0.5
            actual_start, actual_end = t2, t1
          else
            # Wrap-around case: t1=0.0, t2=0.958 means we go from 0.0 backwards
            # which wraps to 1.0 and goes down to 0.958
            # So the actual segment is from t2 to 1.0 (the small piece at the end)
            actual_start, actual_end = t2, 1.0
          end
        else
          if t1 < t2
            actual_start, actual_end = t1, t2
          else
            # Wrap-around in forward direction
            actual_start, actual_end = t1, 1.0
          end
        end

        grain_dir = analyzer.optimal_grain_direction(actual_start, actual_end)
        bounds = analyzer.piece_bounds(actual_start, actual_end)
        piece_pts = analyzer.piece_points(actual_start, actual_end)

        next unless bounds && piece_pts && piece_pts.length > 2

        # Calculate grain angle in degrees for display
        grain_angle = Math.atan2(grain_dir[1], grain_dir[0]) * 180 / Math::PI

        piece_num = i + 1
        puts "  Piece #{piece_num}: t=#{actual_start.round(3)}-#{actual_end.round(3)}, grain angle: #{grain_angle.round(1)}°"

        # Generate grain lines
        grain_lines << generate_grain_lines_for_piece(grain_dir, bounds, piece_pts, path_data, actual_start, actual_end)
      end
    end

    # Extract dimensions
    width = svg_content[/width="([^"]+)"/, 1].to_f
    height = svg_content[/height="([^"]+)"/, 1].to_f
    viewbox_match = svg_content.match(/viewBox="([^"]+)"/)
    viewbox = viewbox_match ? viewbox_match[1].split.map(&:to_f) : [0, 0, width, height]

    # Calculate padded dimensions
    padded_width = width + (SVG_PADDING * 2)
    padded_height = height + (SVG_PADDING * 2)
    padded_viewbox = [
      viewbox[0] - SVG_PADDING,
      viewbox[1] - SVG_PADDING,
      viewbox[2] + (SVG_PADDING * 2),
      viewbox[3] + (SVG_PADDING * 2)
    ].map { |v| v.round(4) }.join(' ')

    # Build modified SVG with padding
    # Create a larger background rect that covers the padded area
    bg_rect = %(<rect x="#{viewbox[0] - SVG_PADDING}" y="#{viewbox[1] - SVG_PADDING}" width="#{viewbox[2] + SVG_PADDING * 2}" height="#{viewbox[3] + SVG_PADDING * 2}" fill="white"/>)
    split_group = %(<g id="split-lines">\n#{split_lines.join("\n")}\n</g>)
    label_group = %(<g id="split-labels">\n#{split_labels.join("\n")}\n</g>)

    # Create ghost track if enabled (thin line for comparison)
    ghost_track = ""
    if SHOW_GHOST_TRACK
      ghost_style = GHOST_TRACK_STYLE == 'dashed' ? 'stroke-dasharray="10,5"' : ''
      ghost_track = %(<g id="ghost-track" opacity="#{GHOST_TRACK_OPACITY}">
<path d="#{path_data}" stroke="#{GHOST_TRACK_COLOR}" stroke-width="2" fill="none" #{ghost_style}/>
</g>)
    end

    # Create railroad-style main track with truly transparent gap using SVG mask
    inner_gap_width = TRACK_OUTER_WIDTH - (TRACK_RAIL_WIDTH * 2)

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

    main_track = %(<defs>
<mask id="railroad-mask">
<path d="#{path_data}" stroke="white" stroke-width="#{TRACK_OUTER_WIDTH}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
<path d="#{path_data}" stroke="black" stroke-width="#{inner_gap_width}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
</mask>
#{grain_clip_paths.join("\n")}
</defs>
<g id="main-track">
<path d="#{path_data}" stroke="#{TRACK_COLOR}" stroke-width="#{TRACK_OUTER_WIDTH}" stroke-linecap="round" stroke-linejoin="round" fill="none" mask="url(#railroad-mask)"/>
</g>)

    # Create grain direction group - uses per-piece polygon clip paths
    grain_group = ""
    if grain_groups.any?
      grain_group = %(<g id="grain-direction">\n#{grain_groups.join("\n")}\n</g>)
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

    # Insert grain direction, split lines, and labels before closing </svg>
    modified_svg = modified_svg.sub(/<\/svg>/, "#{grain_group}\n#{split_group}\n#{label_group}\n</svg>")

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
puts "Configuration Summary:"
puts "  Car dimensions: #{CAR_LENGTH_MM}mm x #{CAR_WIDTH_MM}mm"
puts "  Track width: #{TRACK_WIDTH_MM}mm"
puts "  Min turn radius: #{MIN_TURN_RADIUS_MM}mm"
puts "  Max piece length: #{MAX_PIECE_LENGTH_MM}mm"
puts "  Max assembled size: #{MAX_TRACK_DIMENSION_MM}mm (#{(MAX_TRACK_DIMENSION_MM / 25.4).round(1)} inches)"

puts ""
print 'Opening in Cursor...'
system("cursor", OUTPUT_FILE)
