# Track Segmenter
# Analyzes a track and extracts a sequence of geometric primitives (arcs + straights)
# This primitive chain can then be used to rebuild the track with manual edits

class TrackSegmenter
  # Curvature threshold to distinguish straights from turns
  # Below this curvature (1/radius), a section is considered straight
  CURVATURE_THRESHOLD = 0.015  # Corresponds to ~66" radius

  # Minimum segment length in inches to avoid tiny fragments
  MIN_SEGMENT_LENGTH = 0.5

  # Minimum turn angle to report (degrees)
  MIN_TURN_ANGLE = 5

  attr_reader :primitives

  def initialize(analyzer, start_t: 0.0)
    @analyzer = analyzer
    @start_t = start_t  # Where to start the analysis (normalized t, 0.0 = start/finish)
    @primitives = []
  end

  # Analyze the track and extract primitives
  # Returns an array of primitive definitions
  def segment
    points = @analyzer.points
    curvatures = @analyzer.instance_variable_get(:@curvatures)
    tangents = @analyzer.instance_variable_get(:@tangents)

    return [] if points.length < 3

    # Convert start_t to index
    # Note: points are in raw t order, but we want to process in racing order
    # Racing direction is opposite to raw t direction
    total_pts = points.length

    # Find starting index
    start_idx = (@start_t * (total_pts - 1)).round
    start_idx = [[start_idx, 0].max, total_pts - 1].min

    @primitives = []
    current_segment = nil

    # Process points in racing order (decreasing raw t index)
    # Tangents need to be negated since they point in raw t direction, not racing
    (0...total_pts).each do |raw_i|
      # Wrap around from start point, going in racing direction
      i = (start_idx - raw_i + total_pts) % total_pts

      curv = curvatures[i] || 0
      pt = points[i]
      # Negate tangent to get racing direction
      raw_tangent = tangents[i] || [1, 0]
      tangent = [-raw_tangent[0], -raw_tangent[1]]

      # Determine if this point is on a straight or turn
      is_straight = curv.abs < CURVATURE_THRESHOLD

      if current_segment.nil?
        # Start first segment
        current_segment = new_segment(is_straight, pt, tangent, curv)
      elsif is_straight == current_segment[:is_straight]
        # Continue current segment
        extend_segment(current_segment, pt, tangent, curv)
      else
        # Segment type changed - finalize current and start new
        finalize_segment(current_segment)
        @primitives << current_segment unless current_segment[:length] < MIN_SEGMENT_LENGTH
        current_segment = new_segment(is_straight, pt, tangent, curv)
      end
    end

    # Finalize last segment
    if current_segment
      finalize_segment(current_segment)
      @primitives << current_segment unless current_segment[:length] < MIN_SEGMENT_LENGTH
    end

    # Merge the last and first segments if they're the same type
    # (since we're analyzing a closed loop)
    if @primitives.length >= 2 && @primitives.first[:is_straight] == @primitives.last[:is_straight]
      merge_first_last_segments
    end

    # Convert internal segment format to output primitive format
    @primitives = @primitives.map { |seg| segment_to_primitive(seg) }

    @primitives
  end

  # Generate Ruby code for BLUE_TRACK_DEFINITION
  def generate_definition_code
    return "" if @primitives.empty?

    lines = ["BLUE_TRACK_DEFINITION = ["]

    @primitives.each_with_index do |prim, i|
      comma = i < @primitives.length - 1 ? "," : ""

      case prim[:type]
      when :straight
        lines << "  { type: :straight, length: #{prim[:length].round(2)} }#{comma}"
      when :turn
        dir_sym = prim[:direction] == :left ? ":left" : ":right"
        lines << "  { type: :turn, radius: #{prim[:radius].round(2)}, angle: #{prim[:angle].round(1)}, direction: #{dir_sym} }#{comma}"
      end
    end

    lines << "]"
    lines.join("\n")
  end

  # Print analysis summary
  def print_summary
    puts ""
    puts "=" * 60
    puts "TRACK PRIMITIVE CHAIN ANALYSIS"
    puts "=" * 60

    total_length = 0
    total_turn_angle = 0
    net_turn_angle = 0

    @primitives.each_with_index do |prim, i|
      case prim[:type]
      when :straight
        puts "  #{i + 1}. STRAIGHT: #{prim[:length].round(2)}\""
        total_length += prim[:length]
      when :turn
        arc_len = prim[:radius] * prim[:angle] * Math::PI / 180
        puts "  #{i + 1}. TURN: radius=#{prim[:radius].round(2)}\", angle=#{prim[:angle].round(1)}deg, #{prim[:direction]}"
        total_length += arc_len
        total_turn_angle += prim[:angle]
        # Track net angle (right = positive, left = negative)
        net_turn_angle += prim[:direction] == :right ? prim[:angle] : -prim[:angle]
      end
    end

    puts "-" * 60
    puts "Total primitives: #{@primitives.length}"
    puts "Total length: #{total_length.round(2)}\""
    puts "Total turn angle (sum of magnitudes): #{total_turn_angle.round(1)} degrees"
    puts "Net turn angle (right - left): #{net_turn_angle.round(1)} degrees"
    puts "  (Should be ~360 for clockwise track, ~-360 for counter-clockwise)"
    puts "=" * 60
    puts ""
  end

  private

  def new_segment(is_straight, pt, tangent, curv)
    {
      is_straight: is_straight,
      start_pt: pt.dup,
      end_pt: pt.dup,
      start_tangent: tangent.dup,
      end_tangent: tangent.dup,
      points: [pt.dup],
      curvatures: [curv],
      length: 0.0
    }
  end

  def extend_segment(seg, pt, tangent, curv)
    # Calculate distance from previous point
    prev_pt = seg[:end_pt]
    dist = Math.sqrt((pt[0] - prev_pt[0])**2 + (pt[1] - prev_pt[1])**2)

    seg[:end_pt] = pt.dup
    seg[:end_tangent] = tangent.dup
    seg[:points] << pt.dup
    seg[:curvatures] << curv
    seg[:length] += dist
  end

  def finalize_segment(seg)
    # Recalculate length more accurately
    total_len = 0.0
    pts = seg[:points]
    (1...pts.length).each do |i|
      total_len += Math.sqrt((pts[i][0] - pts[i-1][0])**2 + (pts[i][1] - pts[i-1][1])**2)
    end
    seg[:length] = total_len

    # For turns, calculate average curvature and turn direction
    if !seg[:is_straight] && seg[:curvatures].length > 0
      # Filter out very low curvatures
      valid_curvs = seg[:curvatures].select { |c| c.abs > 0.001 }
      if valid_curvs.any?
        seg[:avg_curvature] = valid_curvs.sum / valid_curvs.length
        seg[:radius] = 1.0 / seg[:avg_curvature]
      else
        seg[:avg_curvature] = 0.001
        seg[:radius] = 1000.0
      end

      # Calculate angle from arc length and radius: angle = arc_length / radius
      # This is more accurate than comparing tangent vectors
      angle_rad = seg[:length] / seg[:radius]
      seg[:angle] = angle_rad * 180 / Math::PI

      # Calculate turn direction using cross product of consecutive point vectors
      # Sum up all the small turns to get the net direction
      total_cross = 0.0
      (1...pts.length - 1).each do |i|
        v1 = [pts[i][0] - pts[i-1][0], pts[i][1] - pts[i-1][1]]
        v2 = [pts[i+1][0] - pts[i][0], pts[i+1][1] - pts[i][1]]
        total_cross += v1[0] * v2[1] - v1[1] * v2[0]
      end

      # In SVG coordinates (Y increases downward):
      # Positive cross product = clockwise = visual right turn
      # Negative cross product = counter-clockwise = visual left turn
      seg[:direction] = total_cross >= 0 ? :right : :left
    end
  end

  def merge_first_last_segments
    first = @primitives.first
    last = @primitives.last

    # Merge last into first (since first comes earlier in racing order)
    first[:start_pt] = last[:start_pt]
    first[:start_tangent] = last[:start_tangent]
    first[:points] = last[:points] + first[:points]
    first[:curvatures] = last[:curvatures] + first[:curvatures]
    first[:length] += last[:length]

    # Re-finalize merged segment
    finalize_segment(first)

    # Remove last segment
    @primitives.pop
  end

  def segment_to_primitive(seg)
    if seg[:is_straight]
      { type: :straight, length: seg[:length] }
    else
      angle = seg[:angle] || 0
      angle = MIN_TURN_ANGLE if angle < MIN_TURN_ANGLE

      {
        type: :turn,
        radius: seg[:radius] || 10.0,
        angle: angle,
        direction: seg[:direction] || :right
      }
    end
  end
end
