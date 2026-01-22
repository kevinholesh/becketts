# Original prompt to claude
# I want to generate the SVG shape of each piece of the track. When assembled, it will resemble a mostly accurate but simplified version of the Silverstone circuit F1 track. I want to optimize for wood grain as long grain as much as I can. I’ll be cutting these out of a CNc machine in walnut. Eventually, I want to write a Ruby script to take a folder full of race track SVGs and generate all of the pieces for each track, finding common pieces to make between them and simplifying some of the curves to make them reusable between different tracks. At least one piece for each track should be totally custom based on the most famous curve on the race track (like Becketts for Silverstone). 
# For now, let’s just start simpler though and just do Silverstone. Help me through how to divide up the track into pieces, how many pieces I’d need to manufacturer. I’m going to be using Hot Wheels Premium F1 cars as the toy on the track, so keep that in mind with the turning radius and minimum “chicane” type diameter. I think that will determine the size of the rest of the track.
# Single lane. I’d prefer to keep it as small as possible. Yes they will connect, similar to a Brio connection with a thin part and a circle as the positive, then a “keyhole” type negative section of the next piece.
# How big would the track have to be? I think max is like it to be 5 feet across in the largest dimension at the very very most. I’m okay not keeping 1:1 scaling between the curves and the straights. I want to simplify and “charactureize” the track circuit to make it easier and cheaper to manufacture.





#!/usr/bin/env ruby
# frozen_string_literal: true

# Track Piece Generator
# Converts race track SVG centerlines into modular wooden track pieces
# for Hot Wheels Premium F1 cars with Brio-style connectors
#
# Usage: ruby track_piece_generator.rb input.svg
#
# Edit the CONFIGURATION section below to adjust parameters

require 'fileutils'
require 'json'
require 'time'

#===============================================================================
# CONFIGURATION - Edit these values to customize your track
#===============================================================================

# Track constraints
MIN_RADIUS_MM = 200              # Minimum curve radius - 200mm for Hot Wheels Premium F1
MAX_PIECE_LENGTH_MM = 350        # Maximum length of a single piece
MIN_PIECE_LENGTH_MM = 80         # Minimum length before pieces get merged
MAX_TOTAL_WIDTH_MM = 1200        # Maximum overall track width (~47")
MAX_TOTAL_HEIGHT_MM = 800        # Maximum overall track height (~31")

# Caricature level: 0.0 = detailed, 1.0 = very simplified
# Higher values reduce piece count but lose detail
SIMPLIFICATION_LEVEL = 0.4

# Curvature detection threshold
# Lower = more sensitive (detects gentler curves as curves)
# Higher = less sensitive (only tight curves detected, more straights)
CURVATURE_THRESHOLD = 0.003

# Track piece dimensions (mm)
TRACK_WIDTH_MM = 40              # Width of track surface
WALL_HEIGHT_MM = 12              # Height of side walls
GROOVE_WIDTH_MM = 10             # Width of center groove for wheels
GROOVE_DEPTH_MM = 3              # Depth of center groove

# Brio-style connector dimensions (mm)
CONNECTOR_PEG_DIAMETER_MM = 12   # Male connector peg diameter
CONNECTOR_HOLE_DIAMETER_MM = 15  # Female connector hole diameter (larger for play)
CONNECTOR_STEM_LENGTH_MM = 10    # Length of connector stem

# Output settings
OUTPUT_DIR = "./output"          # Output directory (relative to input file)

#===============================================================================
# END CONFIGURATION - Code below handles the generation
#===============================================================================

class Vector2D
  attr_accessor :x, :y

  def initialize(x, y)
    @x = x.to_f
    @y = y.to_f
  end

  def +(other) = Vector2D.new(@x + other.x, @y + other.y)
  def -(other) = Vector2D.new(@x - other.x, @y - other.y)
  def *(scalar) = Vector2D.new(@x * scalar, @y * scalar)
  def /(scalar) = Vector2D.new(@x / scalar, @y / scalar)
  def dot(other) = @x * other.x + @y * other.y
  def cross(other) = @x * other.y - @y * other.x
  def magnitude = Math.sqrt(@x * @x + @y * @y)
  def normalize
    mag = magnitude
    return Vector2D.new(0, 0) if mag.zero?
    self / mag
  end
  def perpendicular = Vector2D.new(-@y, @x)
  def angle = Math.atan2(@y, @x)
  def distance_to(other) = (self - other).magnitude
  def to_s = "(#{@x.round(2)}, #{@y.round(2)})"
end

class TrackPoint
  attr_accessor :position, :tangent, :curvature, :arc_length

  def initialize(position, tangent = nil, curvature = 0, arc_length = 0)
    @position = position
    @tangent = tangent || Vector2D.new(1, 0)
    @curvature = curvature
    @arc_length = arc_length
  end
end

class TrackPiece
  attr_accessor :id, :name, :piece_type, :points, :start_angle, :end_angle,
                :arc_length, :radius, :sweep_angle, :is_signature

  def initialize(id)
    @id = id
    @name = "Piece_#{id}"
    @piece_type = :straight
    @points = []
    @start_angle = 0
    @end_angle = 0
    @arc_length = 0
    @radius = Float::INFINITY
    @sweep_angle = 0
    @is_signature = false
  end

  def start_point = @points.first&.position
  def end_point = @points.last&.position
  def start_tangent = @points.first&.tangent || Vector2D.new(1, 0)
  def end_tangent = @points.last&.tangent || Vector2D.new(1, 0)

  def direction
    return :straight if @piece_type == :straight
    return :straight unless @points.length >= 2
    cross = start_tangent.cross(end_tangent)
    cross > 0 ? :left : :right
  end

  def to_inventory_entry
    {
      id: @id,
      name: @name,
      type: @piece_type == :straight ? "Straight" : "Curve #{direction.to_s.capitalize}",
      arc_length: @arc_length.round(1),
      radius: @radius.finite? ? @radius.round(1) : nil,
      sweep_angle_deg: (@sweep_angle * 180 / Math::PI).round(1),
      is_signature: @is_signature
    }
  end
end

class SVGPathParser
  COMMANDS = /([MmZzLlHhVvCcSsQqTtAa])/

  def initialize(path_string)
    @path_string = path_string.strip
    @points = []
    @current_pos = Vector2D.new(0, 0)
  end

  def parse
    return @points unless @points.empty?
    tokens = tokenize(@path_string)
    i = 0
    while i < tokens.length
      cmd = tokens[i]
      i += 1
      args, i = extract_args(tokens, i)
      process_command(cmd, args)
    end
    @points
  end

  private

  def tokenize(path_string)
    tokens = []
    path_string.split(COMMANDS).each do |part|
      part = part.strip
      next if part.empty?
      if part.match?(COMMANDS)
        tokens << part
      else
        tokens.concat(part.scan(/-?[\d.]+(?:e-?\d+)?/i))
      end
    end
    tokens
  end

  def extract_args(tokens, start_idx)
    args = []
    idx = start_idx
    while idx < tokens.length && !tokens[idx].match?(COMMANDS)
      args << tokens[idx].to_f
      idx += 1
    end
    [args, idx]
  end

  def process_command(cmd, args)
    relative = cmd == cmd.downcase
    case cmd.upcase
    when 'M' then move_to(args, relative)
    when 'L' then line_to(args, relative)
    when 'H' then horizontal_to(args, relative)
    when 'V' then vertical_to(args, relative)
    when 'C' then cubic_bezier(args, relative)
    when 'S' then smooth_cubic(args, relative)
    when 'Q' then quadratic_bezier(args, relative)
    when 'A' then arc_to(args, relative)
    when 'Z' then close_path
    end
  end

  def move_to(args, relative)
    args.each_slice(2) do |x, y|
      @current_pos = relative ? @current_pos + Vector2D.new(x, y) : Vector2D.new(x, y)
      @points << @current_pos
    end
  end

  def line_to(args, relative)
    args.each_slice(2) do |x, y|
      target = relative ? @current_pos + Vector2D.new(x, y) : Vector2D.new(x, y)
      interpolate_line(@current_pos, target)
      @current_pos = target
    end
  end

  def horizontal_to(args, relative)
    args.each do |x|
      target = Vector2D.new(relative ? @current_pos.x + x : x, @current_pos.y)
      interpolate_line(@current_pos, target)
      @current_pos = target
    end
  end

  def vertical_to(args, relative)
    args.each do |y|
      target = Vector2D.new(@current_pos.x, relative ? @current_pos.y + y : y)
      interpolate_line(@current_pos, target)
      @current_pos = target
    end
  end

  def cubic_bezier(args, relative)
    args.each_slice(6) do |x1, y1, x2, y2, x, y|
      if relative
        p1, p2, p3 = [@current_pos + Vector2D.new(x1, y1), 
                      @current_pos + Vector2D.new(x2, y2), 
                      @current_pos + Vector2D.new(x, y)]
      else
        p1, p2, p3 = [Vector2D.new(x1, y1), Vector2D.new(x2, y2), Vector2D.new(x, y)]
      end
      interpolate_cubic(@current_pos, p1, p2, p3)
      @current_pos = p3
    end
  end

  def smooth_cubic(args, relative)
    args.each_slice(4) do |x2, y2, x, y|
      p1 = @current_pos
      p2, p3 = relative ? [@current_pos + Vector2D.new(x2, y2), @current_pos + Vector2D.new(x, y)] : 
                          [Vector2D.new(x2, y2), Vector2D.new(x, y)]
      interpolate_cubic(@current_pos, p1, p2, p3)
      @current_pos = p3
    end
  end

  def quadratic_bezier(args, relative)
    args.each_slice(4) do |x1, y1, x, y|
      p1, p2 = relative ? [@current_pos + Vector2D.new(x1, y1), @current_pos + Vector2D.new(x, y)] :
                          [Vector2D.new(x1, y1), Vector2D.new(x, y)]
      interpolate_quadratic(@current_pos, p1, p2)
      @current_pos = p2
    end
  end

  def arc_to(args, relative)
    args.each_slice(7) do |rx, ry, rotation, large_arc, sweep, x, y|
      target = relative ? @current_pos + Vector2D.new(x, y) : Vector2D.new(x, y)
      interpolate_line(@current_pos, target, 20)
      @current_pos = target
    end
  end

  def close_path
    return if @points.empty?
    interpolate_line(@current_pos, @points.first) if @current_pos.distance_to(@points.first) > 0.1
    @current_pos = @points.first
  end

  def interpolate_line(p0, p1, samples = 10)
    (1..samples).each do |i|
      t = i.to_f / samples
      @points << p0 * (1 - t) + p1 * t
    end
  end

  def interpolate_cubic(p0, p1, p2, p3, samples = 20)
    (1..samples).each do |i|
      t = i.to_f / samples
      mt = 1 - t
      x = mt**3 * p0.x + 3 * mt**2 * t * p1.x + 3 * mt * t**2 * p2.x + t**3 * p3.x
      y = mt**3 * p0.y + 3 * mt**2 * t * p1.y + 3 * mt * t**2 * p2.y + t**3 * p3.y
      @points << Vector2D.new(x, y)
    end
  end

  def interpolate_quadratic(p0, p1, p2, samples = 15)
    (1..samples).each do |i|
      t = i.to_f / samples
      mt = 1 - t
      x = mt**2 * p0.x + 2 * mt * t * p1.x + t**2 * p2.x
      y = mt**2 * p0.y + 2 * mt * t * p1.y + t**2 * p2.y
      @points << Vector2D.new(x, y)
    end
  end
end

class PathSimplifier
  def initialize(points, tolerance)
    @points = points
    @tolerance = tolerance
  end

  def simplify
    return @points if @points.length < 3
    douglas_peucker(@points, @tolerance)
  end

  private

  def douglas_peucker(points, epsilon)
    return points if points.length < 3

    max_dist, max_idx = 0, 0
    (1...points.length - 1).each do |i|
      dist = perpendicular_distance(points[i], points.first, points.last)
      max_dist, max_idx = dist, i if dist > max_dist
    end

    if max_dist > epsilon
      left = douglas_peucker(points[0..max_idx], epsilon)
      right = douglas_peucker(points[max_idx..-1], epsilon)
      left[0..-2] + right
    else
      [points.first, points.last]
    end
  end

  def perpendicular_distance(point, line_start, line_end)
    line_vec = line_end - line_start
    point_vec = point - line_start
    line_len = line_vec.magnitude
    return point_vec.magnitude if line_len.zero?
    t = [0, [1, point_vec.dot(line_vec) / (line_len * line_len)].min].max
    (point - (line_start + line_vec * t)).magnitude
  end
end

class CurvatureAnalyzer
  def initialize(points)
    @points = points
  end

  def analyze
    return [] if @points.length < 3
    track_points = []
    arc_length = 0

    @points.each_with_index do |pos, i|
      arc_length += pos.distance_to(@points[i - 1]) if i > 0
      tangent = calculate_tangent(i)
      curvature = calculate_curvature(i)
      track_points << TrackPoint.new(pos, tangent, curvature, arc_length)
    end
    track_points
  end

  private

  def calculate_tangent(idx)
    return (@points[1] - @points[0]).normalize if idx == 0 && @points.length > 1
    return (@points[-1] - @points[-2]).normalize if idx == @points.length - 1 && @points.length > 1
    return Vector2D.new(1, 0) if @points.length <= 1
    ((@points[idx + 1] - @points[idx - 1]) / 2).normalize
  end

  def calculate_curvature(idx)
    return 0 if idx < 1 || idx >= @points.length - 1
    p0, p1, p2 = @points[idx - 1], @points[idx], @points[idx + 1]
    a, b, c = p0.distance_to(p1), p1.distance_to(p2), p2.distance_to(p0)
    return 0 if [a, b, c].any? { |d| d < 0.001 }
    area = ((p1 - p0).cross(p2 - p0)) / 2
    (4 * area) / (a * b * c)
  end
end

class TrackSegmenter
  def initialize(track_points)
    @track_points = track_points
  end

  def segment
    return [] if @track_points.empty?

    pieces = []
    current_piece = TrackPiece.new(1)
    current_piece.points << @track_points.first

    @track_points.each_cons(2).with_index do |(prev_point, curr_point), idx|
      current_piece.points << curr_point
      piece_length = curr_point.arc_length - current_piece.points.first.arc_length

      should_split = piece_length >= MAX_PIECE_LENGTH_MM

      if idx > 0 && !should_split && piece_length >= MIN_PIECE_LENGTH_MM
        prev_straight = prev_point.curvature.abs < CURVATURE_THRESHOLD
        curr_straight = curr_point.curvature.abs < CURVATURE_THRESHOLD
        should_split = prev_straight != curr_straight
      end

      if idx > 0 && !should_split && piece_length >= MIN_PIECE_LENGTH_MM
        should_split = prev_point.curvature * curr_point.curvature < 0 &&
                       [prev_point, curr_point].all? { |p| p.curvature.abs > CURVATURE_THRESHOLD }
      end

      if should_split
        finalize_piece(current_piece)
        pieces << current_piece
        current_piece = TrackPiece.new(pieces.length + 1)
        current_piece.points << curr_point
      end
    end

    finalize_piece(current_piece) if current_piece.points.length > 1
    pieces << current_piece unless current_piece.points.length <= 1
    merge_short_pieces(pieces)
  end

  private

  def finalize_piece(piece)
    return if piece.points.empty?
    piece.arc_length = piece.points.last.arc_length - piece.points.first.arc_length
    piece.start_angle = piece.points.first.tangent.angle
    piece.end_angle = piece.points.last.tangent.angle
    piece.sweep_angle = normalize_angle(piece.end_angle - piece.start_angle)

    max_curv = piece.points.map { |p| p.curvature.abs }.max
    if max_curv < CURVATURE_THRESHOLD
      piece.piece_type = :straight
      piece.radius = Float::INFINITY
    else
      piece.piece_type = :curve
      non_zero = piece.points.map(&:curvature).reject { |c| c.abs < 0.0001 }
      if non_zero.any?
        piece.radius = (1.0 / (non_zero.map(&:abs).sum / non_zero.length)).abs
        if piece.radius < MIN_RADIUS_MM
          piece.radius = MIN_RADIUS_MM
          piece.is_signature = true
        end
      end
    end
    piece.name = generate_name(piece)
  end

  def generate_name(piece)
    if piece.piece_type == :straight
      "S#{piece.id}_#{piece.arc_length.round(0)}mm"
    else
      dir = piece.direction == :left ? "L" : "R"
      angle = (piece.sweep_angle.abs * 180 / Math::PI).round(0)
      radius = piece.radius.finite? ? piece.radius.round(0) : "INF"
      "C#{piece.id}_#{angle}deg_#{dir}_R#{radius}"
    end
  end

  def normalize_angle(angle)
    angle -= 2 * Math::PI while angle > Math::PI
    angle += 2 * Math::PI while angle < -Math::PI
    angle
  end

  def merge_short_pieces(pieces)
    return pieces if pieces.length < 2
    merged = [pieces.first]
    pieces[1..-1].each do |piece|
      if merged.last.arc_length < MIN_PIECE_LENGTH_MM && merged.last.piece_type == piece.piece_type
        merged.last.points.concat(piece.points[1..-1])
        finalize_piece(merged.last)
      else
        merged << piece
      end
    end
    merged.each_with_index { |p, i| p.id = i + 1 }
    merged
  end
end

class PieceSVGGenerator
  def initialize(piece)
    @piece = piece
  end

  def generate
    points = @piece.points.map(&:position)
    min_x, max_x = points.map(&:x).minmax
    min_y, max_y = points.map(&:y).minmax

    width = max_x - min_x + TRACK_WIDTH_MM + 60
    height = max_y - min_y + TRACK_WIDTH_MM + 60
    offset_x = -min_x + TRACK_WIDTH_MM / 2 + 30
    offset_y = -min_y + TRACK_WIDTH_MM / 2 + 30

    <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width.round(1)} #{height.round(1)}" width="#{width.round(1)}" height="#{height.round(1)}">
        <title>#{@piece.name}</title>
        <rect width="#{width.round(1)}" height="#{height.round(1)}" fill="#fafafa"/>
        <text x="10" y="20" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#333">#{@piece.name}#{@piece.is_signature ? ' ★' : ''}</text>
        <text x="10" y="35" font-family="Arial, sans-serif" font-size="10" fill="#666">Length: #{@piece.arc_length.round(1)}mm | #{@piece.radius.finite? ? "R=#{@piece.radius.round(1)}mm" : "Straight"}</text>
        <g transform="translate(#{offset_x.round(2)}, #{offset_y.round(2)})">
          #{generate_track_body(points)}
          #{generate_groove(points)}
          #{generate_connectors(points)}
        </g>
        #{generate_grain_indicator(width, height)}
      </svg>
    SVG
  end

  private

  def generate_track_body(points)
    return "" if points.length < 2
    left = offset_path(points, TRACK_WIDTH_MM / 2)
    right = offset_path(points, -TRACK_WIDTH_MM / 2)
    path_d = "M #{left.first.x.round(2)},#{left.first.y.round(2)} "
    left[1..-1].each { |p| path_d += "L #{p.x.round(2)},#{p.y.round(2)} " }
    right.reverse.each { |p| path_d += "L #{p.x.round(2)},#{p.y.round(2)} " }
    color = @piece.is_signature ? "#6B3410" : "#d4a574"
    stroke = @piece.is_signature ? "#4D2A0F" : "#8B4513"
    %(<path d="#{path_d}Z" fill="#{color}" stroke="#{stroke}" stroke-width="1.5"/>)
  end

  def generate_groove(points)
    return "" if points.length < 2
    path_d = "M #{points.first.x.round(2)},#{points.first.y.round(2)} "
    points[1..-1].each { |p| path_d += "L #{p.x.round(2)},#{p.y.round(2)} " }
    %(<path d="#{path_d}" fill="none" stroke="#5D3A1A" stroke-width="#{GROOVE_WIDTH_MM}" stroke-linecap="round"/>)
  end

  def generate_connectors(points)
    return "" if points.length < 2
    generate_female_connector(points.first, @piece.start_tangent * -1) +
    generate_male_connector(points.last, @piece.end_tangent)
  end

  def generate_female_connector(pos, dir)
    dir = dir.normalize
    hole_center = pos + dir * 5
    <<~SVG
      <circle cx="#{hole_center.x.round(2)}" cy="#{hole_center.y.round(2)}" r="#{(CONNECTOR_HOLE_DIAMETER_MM/2).round(2)}" fill="#fafafa" stroke="#8B4513" stroke-width="1"/>
    SVG
  end

  def generate_male_connector(pos, dir)
    dir = dir.normalize
    stem_end = pos + dir * CONNECTOR_STEM_LENGTH_MM
    peg_center = stem_end + dir * (CONNECTOR_PEG_DIAMETER_MM / 2)
    <<~SVG
      <line x1="#{pos.x.round(2)}" y1="#{pos.y.round(2)}" x2="#{stem_end.x.round(2)}" y2="#{stem_end.y.round(2)}" stroke="#8B4513" stroke-width="#{(CONNECTOR_PEG_DIAMETER_MM * 0.6).round(2)}"/>
      <circle cx="#{peg_center.x.round(2)}" cy="#{peg_center.y.round(2)}" r="#{(CONNECTOR_PEG_DIAMETER_MM/2).round(2)}" fill="#8B4513" stroke="#5D3A1A" stroke-width="1"/>
    SVG
  end

  def offset_path(points, distance)
    points.each_with_index.map do |point, i|
      tangent = if i == 0 then (points[1] - points[0]).normalize
                elsif i == points.length - 1 then (points[-1] - points[-2]).normalize
                else ((points[i + 1] - points[i - 1]) / 2).normalize
                end
      point + tangent.perpendicular * distance
    end
  end

  def generate_grain_indicator(width, height)
    avg_tan = ((@piece.start_tangent + @piece.end_tangent) / 2).normalize
    sx, sy = width - 80, height - 25
    ex, ey = sx + avg_tan.x * 40, sy + avg_tan.y * 40
    <<~SVG
      <g>
        <line x1="#{sx.round(2)}" y1="#{sy.round(2)}" x2="#{ex.round(2)}" y2="#{ey.round(2)}" stroke="#8B4513" stroke-width="2"/>
        <polygon points="#{ex.round(2)},#{ey.round(2)} #{(ex - 5*avg_tan.x + 3*avg_tan.y).round(2)},#{(ey - 5*avg_tan.y - 3*avg_tan.x).round(2)} #{(ex - 5*avg_tan.x - 3*avg_tan.y).round(2)},#{(ey - 5*avg_tan.y + 3*avg_tan.x).round(2)}" fill="#8B4513"/>
        <text x="#{(sx - 10).round(2)}" y="#{(sy + 5).round(2)}" font-family="Arial, sans-serif" font-size="8" fill="#8B4513">GRAIN</text>
      </g>
    SVG
  end
end

class TrackPieceGenerator
  def initialize(input_file)
    @input_file = input_file
    @track_name = File.basename(input_file, ".*").gsub(/[^a-zA-Z0-9]/, "_")
    @pieces = []
    @output_dir = File.join(File.dirname(File.expand_path(input_file)), OUTPUT_DIR)
  end

  def process
    puts "=" * 60
    puts "TRACK PIECE GENERATOR"
    puts "=" * 60
    puts "\nInput:  #{@input_file}"
    puts "Output: #{@output_dir}\n\n"
    puts "Configuration:"
    puts "  Min radius:       #{MIN_RADIUS_MM}mm"
    puts "  Max piece length: #{MAX_PIECE_LENGTH_MM}mm"
    puts "  Track width:      #{TRACK_WIDTH_MM}mm"
    puts "  Simplification:   #{SIMPLIFICATION_LEVEL}"
    puts "  Max dimensions:   #{MAX_TOTAL_WIDTH_MM} × #{MAX_TOTAL_HEIGHT_MM}mm\n\n"

    svg_content = File.read(@input_file, encoding: 'UTF-8')
    path_data = extract_path(svg_content)
    return puts("ERROR: No path data found in SVG") || false if path_data.nil?

    puts "Parsing SVG path..."
    raw_points = SVGPathParser.new(path_data).parse
    puts "  Found #{raw_points.length} points"

    scaled = scale_to_fit(raw_points)
    puts "  Scaled to fit within #{MAX_TOTAL_WIDTH_MM}×#{MAX_TOTAL_HEIGHT_MM}mm"

    tolerance = SIMPLIFICATION_LEVEL * 20
    simplified = PathSimplifier.new(scaled, tolerance).simplify
    puts "  Simplified to #{simplified.length} points"

    track_points = CurvatureAnalyzer.new(simplified).analyze
    @pieces = TrackSegmenter.new(track_points).segment
    puts "  Segmented into #{@pieces.length} pieces\n\n"

    generate_output
    true
  end

  private

  def extract_path(svg)
    svg = svg.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    paths = svg.scan(/<path[^>]*d="([^"]+)"[^>]*>/i) + svg.scan(/<path[^>]*d='([^']+)'[^>]*>/i)
    paths.flatten.max_by(&:length)
  end

  def scale_to_fit(points)
    return points if points.empty?
    min_x, max_x = points.map(&:x).minmax
    min_y, max_y = points.map(&:y).minmax
    w, h = max_x - min_x, max_y - min_y
    return points if w.zero? || h.zero?
    scale = [MAX_TOTAL_WIDTH_MM / w, MAX_TOTAL_HEIGHT_MM / h].min
    cx, cy = (min_x + max_x) / 2, (min_y + max_y) / 2
    points.map { |p| Vector2D.new((p.x - cx) * scale, (p.y - cy) * scale) }
  end

  def generate_output
    FileUtils.mkdir_p(@output_dir)
    pieces_dir = File.join(@output_dir, "pieces")
    FileUtils.mkdir_p(pieces_dir)

    generate_layout_svg
    @pieces.each { |p| generate_piece_svg(p, pieces_dir) }
    generate_inventory

    puts "\n" + "=" * 60
    puts "Output generated in: #{@output_dir}"
    puts "=" * 60
  end

  def generate_layout_svg
    all_points = @pieces.flat_map { |p| p.points.map(&:position) }
    min_x, max_x = all_points.map(&:x).minmax
    min_y, max_y = all_points.map(&:y).minmax
    width, height = max_x - min_x + 100, max_y - min_y + 150
    offset_x, offset_y = -min_x + 50, -min_y + 100

    colors = %w[#8B4513 #A0522D #CD853F #DEB887 #D2691E #B8860B #DAA520 #F4A460]

    svg = <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width.round(1)} #{height.round(1)}" width="#{width.round(1)}" height="#{height.round(1)}">
        <title>#{@track_name} - Layout</title>
        <rect width="#{width.round(1)}" height="#{height.round(1)}" fill="#f5f5f0"/>
        <text x="#{(width/2).round(1)}" y="30" text-anchor="middle" font-family="Arial, sans-serif" font-size="20" font-weight="bold" fill="#333">#{@track_name.upcase}</text>
        <text x="#{(width/2).round(1)}" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="#666">#{@pieces.length} pieces | #{@pieces.count(&:is_signature)} signature | Total: #{@pieces.sum(&:arc_length).round(0)}mm</text>
        <g transform="translate(#{offset_x.round(2)}, #{offset_y.round(2)})">
    SVG

    @pieces.each_with_index do |piece, idx|
      color = piece.is_signature ? "#8B0000" : colors[idx % colors.length]
      points = piece.points.map(&:position)
      next if points.length < 2

      left = offset_path_simple(points, TRACK_WIDTH_MM / 2)
      right = offset_path_simple(points, -TRACK_WIDTH_MM / 2)
      path_d = "M #{left.first.x.round(2)},#{left.first.y.round(2)} "
      left[1..-1].each { |p| path_d += "L #{p.x.round(2)},#{p.y.round(2)} " }
      right.reverse.each { |p| path_d += "L #{p.x.round(2)},#{p.y.round(2)} " }

      mid = points[points.length / 2]
      svg += %(<g><path d="#{path_d}Z" fill="#{color}" stroke="#333" stroke-width="1" opacity="0.8"/>)
      svg += %(<text x="#{mid.x.round(2)}" y="#{mid.y.round(2)}" font-family="Arial" font-size="10" fill="white" text-anchor="middle" stroke="#333" stroke-width="0.5">#{piece.id}</text></g>\n)
    end

    svg += %(</g><text x="20" y="#{height - 15}" font-family="Arial" font-size="10" fill="#666">★ = Signature piece</text></svg>)

    path = File.join(@output_dir, "#{@track_name}_layout.svg")
    File.write(path, svg)
    puts "Generated: #{path}"
  end

  def offset_path_simple(points, distance)
    points.each_with_index.map do |point, i|
      tangent = if i == 0 then (points[1] - points[0]).normalize
                elsif i == points.length - 1 then (points[-1] - points[-2]).normalize
                else ((points[i + 1] - points[i - 1]) / 2).normalize
                end
      point + tangent.perpendicular * distance
    end
  end

  def generate_piece_svg(piece, dir)
    svg = PieceSVGGenerator.new(piece).generate
    path = File.join(dir, "#{piece.name}.svg")
    File.write(path, svg)
    puts "Generated: #{path}"
  end

  def generate_inventory
    inv = {
      track_name: @track_name,
      generated_at: Time.now.iso8601,
      parameters: { min_radius: MIN_RADIUS_MM, max_piece_length: MAX_PIECE_LENGTH_MM,
                    track_width: TRACK_WIDTH_MM, simplification: SIMPLIFICATION_LEVEL },
      summary: { total: @pieces.length, straights: @pieces.count { |p| p.piece_type == :straight },
                 curves: @pieces.count { |p| p.piece_type == :curve },
                 signature: @pieces.count(&:is_signature),
                 total_length: @pieces.sum(&:arc_length).round(1) },
      pieces: @pieces.map(&:to_inventory_entry)
    }

    File.write(File.join(@output_dir, "#{@track_name}_inventory.json"), JSON.pretty_generate(inv))
    puts "Generated: #{@output_dir}/#{@track_name}_inventory.json"

    txt = generate_text_inventory(inv)
    File.write(File.join(@output_dir, "#{@track_name}_inventory.txt"), txt)
    puts "Generated: #{@output_dir}/#{@track_name}_inventory.txt"
  end

  def generate_text_inventory(inv)
    lines = ["=" * 70, "#{inv[:track_name].upcase} - PIECE INVENTORY", "=" * 70, "",
             "Generated: #{inv[:generated_at]}", "", "CONFIGURATION:", "-" * 40]
    inv[:parameters].each { |k, v| lines << "  #{k}: #{v}" }
    lines += ["", "SUMMARY:", "-" * 40]
    inv[:summary].each { |k, v| lines << "  #{k}: #{v}" }
    lines += ["", "PIECES:", "-" * 70,
              sprintf("%-4s %-30s %-15s %10s %10s", "ID", "Name", "Type", "Length", "Radius"), "-" * 70]
    inv[:pieces].each do |p|
      sig = p[:is_signature] ? "★" : " "
      lines << sprintf("%s%-3s %-30s %-15s %10s %10s", sig, p[:id], p[:name], p[:type],
                       "#{p[:arc_length]}mm", p[:radius] ? "#{p[:radius]}mm" : "∞")
    end
    lines << "-" * 70
    lines << "\n★ = Signature piece (minimum radius)"
    lines.join("\n")
  end
end

# Entry point
if ARGV.empty?
  puts "Usage: ruby #{$0} INPUT_SVG"
  puts "\nEdit the CONFIGURATION section at the top of this file to adjust parameters."
  exit 1
end

unless File.exist?(ARGV[0])
  puts "Error: File not found: #{ARGV[0]}"
  exit 1
end

exit(TrackPieceGenerator.new(ARGV[0]).process ? 0 : 1)
