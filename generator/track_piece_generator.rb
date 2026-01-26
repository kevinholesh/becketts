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
TRACK_WIDTH_MM = 50.0     # Lane width - enough clearance for the car
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

# Chicane protection - keep tight S-curves as single pieces
CHICANE_PROTECTION = true         # Enable chicane detection
CHICANE_ANGLE_THRESHOLD = 60.0    # Degrees - direction change that indicates a chicane
CHICANE_MIN_REVERSALS = 2         # Minimum direction reversals to qualify as chicane

# Special named pieces - these sections will NOT be split
# Each entry: { name: "Name", t_start: 0.0, t_end: 1.0 }
# Use the track analysis output to find t-values for corners
SPECIAL_PIECES = [
  { name: "Maggots-Becketts-Chapel", t_start: 0.27, t_end: 0.42 },
  # Add more special pieces here, e.g.:
  # { name: "Club Corner", t_start: 0.52, t_end: 0.62 },
]

# Visual settings for split preview
SPLIT_LINE_COLOR = '#FF0000'
SPLIT_LINE_WIDTH = 2.0
SPLIT_LINE_LENGTH = 30.0          # Length of split indicator lines
SVG_PADDING = 40.0                # White border padding around the SVG

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

    # Apply special pieces - remove splits within special piece ranges
    # and add splits at their boundaries
    final_splits = apply_special_pieces(merged)

    # Apply chicane protection
    if CHICANE_PROTECTION
      final_splits = apply_chicane_protection(final_splits)
    end

    final_splits
  end

  def apply_special_pieces(splits)
    return splits if SPECIAL_PIECES.empty?

    result = []
    special_boundaries = []

    # Collect all special piece boundaries
    SPECIAL_PIECES.each do |piece|
      special_boundaries << piece[:t_start]
      special_boundaries << piece[:t_end]
    end

    # Filter out splits that fall within special pieces
    splits.each do |s|
      in_special = SPECIAL_PIECES.any? do |piece|
        s > piece[:t_start] && s < piece[:t_end]
      end

      unless in_special
        result << s
      end
    end

    # Add boundaries of special pieces as split points
    special_boundaries.each do |boundary|
      # Only add if not too close to existing splits
      closest = result.min_by { |s| (s - boundary).abs }
      if closest.nil? || (boundary - closest).abs >= MIN_SPLIT_SPACING * 0.3
        result << boundary
      end
    end

    result.sort.uniq
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
    splits = analyzer.split_points

    puts "Track Analysis:"
    puts "  Total points sampled: #{analyzer.points.length}"
    puts "  Approximate path length: #{analyzer.path_length.round(2)} SVG units"
    puts "  Split points found: #{splits.length}"

    if SPECIAL_PIECES.any?
      puts ""
      puts "Special Pieces (kept as single units):"
      SPECIAL_PIECES.each do |piece|
        start_pt = analyzer.point_at(piece[:t_start])
        end_pt = analyzer.point_at(piece[:t_end])
        puts "  #{piece[:name]}: t=#{piece[:t_start]}-#{piece[:t_end]}"
        puts "    from (#{start_pt[0].round(1)}, #{start_pt[1].round(1)}) to (#{end_pt[0].round(1)}, #{end_pt[1].round(1)})"
      end
    end

    puts ""

    # Generate split lines
    split_lines = []
    splits.each_with_index do |t, i|
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

      puts "  Split #{i + 1}: t=#{t.round(3)} at (#{point[0].round(1)}, #{point[1].round(1)})"
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

    # Update SVG dimensions and viewBox
    modified_svg = svg_content.dup
    modified_svg = modified_svg.sub(/width="[^"]+"/, %(width="#{padded_width.round(2)}"))
    modified_svg = modified_svg.sub(/height="[^"]+"/, %(height="#{padded_height.round(2)}"))
    modified_svg = modified_svg.sub(/viewBox="[^"]+"/, %(viewBox="#{padded_viewbox}"))

    # Insert background right after the opening <svg> tag
    modified_svg = modified_svg.sub(/>(\s*<path)/, ">\n#{bg_rect}\\1")

    # Insert split lines before closing </svg>
    modified_svg = modified_svg.sub(/<\/svg>/, "#{split_group}\n</svg>")

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
