#!/usr/bin/env ruby

# Piece Layout Optimizer for CNC Cutting
# Generates pieces-layed-out.svg with optimized nesting for minimal material waste
# while respecting wood grain direction

require 'set'
require_relative 'track_generator'

#===============================================================================
# GRAIN DIRECTION CONFIGURATION
#===============================================================================
# Manual grain angle overrides for each piece (degrees from vertical)
# 0° = grain runs vertically (along Y axis of board)
# 90° = grain runs horizontally (along X axis of board)
#
# For wood strength:
# - Straight pieces: grain along the length (0° when piece is vertical)
# - Curved pieces: grain should follow the dominant arc direction
#
# These can be adjusted based on your specific wood and cutting requirements

#===============================================================================
# CONFIGURATION - All adjustable parameters
#===============================================================================

# Grain angle overrides for each piece (degrees from vertical)
# 0° = grain runs vertically (along piece length)
GRAIN_OVERRIDES = {
  # Straight pieces - grain along length
  1 => 0,
  4 => 0,
  9 => 2.2,
  7 => -5.1,
  6 => 2.5,
  2 => 0,
  10 => -8,
  8 => 0,

  # Chicane pieces
  11 => 90,
  3 => 90,
  5 => 113,
}

# Grain angle tolerance - pieces can rotate within this for better nesting
GRAIN_ANGLE_TOLERANCE = 5  # degrees

# Board dimensions (inches)
STANDARD_BOARD_LENGTH = 36.0   # Max board length available
NARROW_BOARD_WIDTH = 5.0       # Narrow boards (4-5")
STANDARD_BOARD_WIDTH = 6.0     # Typical board width
WIDE_BOARD_WIDTH = 7.0         # Widest single boards
GLUEUP_PANEL_WIDTH = 14.0      # Glue-up panel width

# Layout parameters
PIECE_MARGIN = 0.25   # Margin around pieces on each board
PIECE_SPACING = PIECE_MARGIN  # Gap between pieces
BOARD_MARGIN = 0.3    # Margin from SVG edges for display

# CNC parameters
CHANNEL_EXTENSION = 0.125  # How far inner channel extends past piece ends (1/8") for clean CNC cuts

# Piece categorization
SOLO_PANEL_PIECES = [5, 11, 3]  # Curvy pieces that get individual glue-up panels
FORCE_SINGLE_BOARD = [8]          # Wide pieces that can still fit on single boards
SOLO_BOARD_PIECES = [2]           # Pieces that get their own dedicated board (no sharing)

# Special nesting configurations for specific piece pairs
# Manual control over positioning:
#   :p1_rotate  - rotation of first piece in degrees (default 0)
#   :p1_x       - x offset of first piece (default 0)
#   :p1_y       - y offset of first piece (default 0)
#   :p2_rotate  - rotation of second piece in degrees (default 0, use 180 for sixty-nine)
#   :p2_x       - x position of second piece relative to group origin
#   :p2_y       - y position of second piece relative to group origin
#
# Pieces are placed with their top-left at (0,0). After rotation, they're repositioned.
# Use positive x to move right, positive y to move down.
NESTING_PAIRS = {
  [10, 7] => { p1_y: 4.0, p2_rotate: 180, p2_x: 1.3, p2_y: 0.0 },
  [9, 4]  => { p2_rotate: 180, p2_x: 2.4, p2_y: 4.0 },
  [6, 1]  => { p2_rotate: 180, p2_x: 2.4, p2_y: 4.0 },
}

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

# Convert decimal inches to fractional string (to nearest 1/16")
def inches_to_fraction(value)
  whole = value.floor
  decimal = value - whole

  # Round to nearest 1/16
  sixteenths = (decimal * 16).round

  return whole.to_s if sixteenths == 0
  return (whole + 1).to_s if sixteenths == 16

  # Simplify the fraction
  numerator = sixteenths
  denominator = 16

  # Find GCD to reduce fraction
  gcd = numerator.gcd(denominator)
  numerator /= gcd
  denominator /= gcd

  if whole == 0
    "#{numerator}/#{denominator}"
  else
    "#{whole}-#{numerator}/#{denominator}"
  end
end

# Calculate polygon area using the shoelace formula
def polygon_area(points)
  return 0 if points.nil? || points.length < 3

  n = points.length
  area = 0.0

  n.times do |i|
    j = (i + 1) % n
    area += points[i][0] * points[j][1]
    area -= points[j][0] * points[i][1]
  end

  (area.abs / 2.0)
end

#===============================================================================
# PIECE DATA STRUCTURE
#===============================================================================

class PieceData
  attr_reader :piece_num, :width, :height, :points, :inner_channel, :outer_boundary, :left_wall, :right_wall
  attr_reader :grain_angle, :rotated_width, :rotated_height
  attr_accessor :x, :y, :rotation, :board_offset, :x_in_group, :rotated_180, :grain_offset

  def initialize(data, inner_width, sidewall_thickness)
    @piece_num = data[:piece_num]
    @points = data[:points]
    @inner_width = inner_width
    @sidewall_thickness = sidewall_thickness
    @total_width = inner_width + (sidewall_thickness * 2)

    # Get grain angle (use override or computed)
    @grain_angle = GRAIN_OVERRIDES[@piece_num] || 0

    process_geometry
  end

  def process_geometry
    return if @points.nil? || @points.length < 2

    # Calculate the principal direction of the piece (start to end)
    start_pt = @points.first
    end_pt = @points.last
    dx = end_pt[0] - start_pt[0]
    dy = end_pt[1] - start_pt[1]

    # Calculate rotation to make piece vertical, then adjust by grain angle
    principal_angle = Math.atan2(dy, dx)
    @rotation = -principal_angle + Math::PI / 2 + (@grain_angle * Math::PI / 180)

    # Rotate all centerline points
    rotated_centerline = @points.map { |p| rotate_point(p, @rotation, start_pt) }

    # Build shapes from rotated centerline
    shapes = build_shapes(rotated_centerline)
    return unless shapes

    @inner_channel = shapes[:inner_channel]
    @outer_boundary = shapes[:outer_boundary]
    @left_wall = shapes[:left_wall]
    @right_wall = shapes[:right_wall]

    # Calculate bounding box
    all_pts = @left_wall + @right_wall
    min_x = all_pts.map { |p| p[0] }.min
    max_x = all_pts.map { |p| p[0] }.max
    min_y = all_pts.map { |p| p[1] }.min
    max_y = all_pts.map { |p| p[1] }.max

    @width = max_x - min_x
    @height = max_y - min_y

    # Normalize to origin
    @inner_channel = @inner_channel.map { |p| [p[0] - min_x, p[1] - min_y] }
    @outer_boundary = @outer_boundary.map { |p| [p[0] - min_x, p[1] - min_y] }
    @left_wall = @left_wall.map { |p| [p[0] - min_x, p[1] - min_y] }
    @right_wall = @right_wall.map { |p| [p[0] - min_x, p[1] - min_y] }

    # Also compute 90° rotated dimensions for layout flexibility
    @rotated_width = @height
    @rotated_height = @width
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

  def build_shapes(points)
    return nil if points.nil? || points.length < 2

    half_total = @total_width / 2.0
    half_inner = @inner_width / 2.0

    outer_left = []
    inner_left = []
    inner_right = []
    outer_right = []

    points.each_with_index do |pt, i|
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

      norm_x = -dy / len
      norm_y = dx / len

      outer_left << [pt[0] + norm_x * half_total, pt[1] + norm_y * half_total]
      inner_left << [pt[0] + norm_x * half_inner, pt[1] + norm_y * half_inner]
      inner_right << [pt[0] - norm_x * half_inner, pt[1] - norm_y * half_inner]
      outer_right << [pt[0] - norm_x * half_total, pt[1] - norm_y * half_total]
    end

    return nil if outer_left.length < 2

    # Add tongue extensions to inner channel for clean CNC cuts
    # Extend the channel past the start and end faces
    if CHANNEL_EXTENSION > 0 && points.length >= 2
      # Start tongue: extend backwards from first point
      start_pt = points[0]
      next_pt = points[1]
      start_dx = next_pt[0] - start_pt[0]
      start_dy = next_pt[1] - start_pt[1]
      start_len = Math.sqrt(start_dx * start_dx + start_dy * start_dy)
      if start_len > 0.001
        # Direction unit vector (pointing forward along track)
        dir_x = start_dx / start_len
        dir_y = start_dy / start_len
        # Normal vector (perpendicular)
        norm_x = -start_dy / start_len
        norm_y = start_dx / start_len

        # Extend backwards by CHANNEL_EXTENSION
        ext_x = start_pt[0] - dir_x * CHANNEL_EXTENSION
        ext_y = start_pt[1] - dir_y * CHANNEL_EXTENSION

        # Add tongue points at the start
        tongue_start_left = [ext_x + norm_x * half_inner, ext_y + norm_y * half_inner]
        tongue_start_right = [ext_x - norm_x * half_inner, ext_y - norm_y * half_inner]
        inner_left.unshift(tongue_start_left)
        inner_right.unshift(tongue_start_right)
      end

      # End tongue: extend forward from last point
      end_pt = points[-1]
      prev_pt = points[-2]
      end_dx = end_pt[0] - prev_pt[0]
      end_dy = end_pt[1] - prev_pt[1]
      end_len = Math.sqrt(end_dx * end_dx + end_dy * end_dy)
      if end_len > 0.001
        # Direction unit vector (pointing forward along track)
        dir_x = end_dx / end_len
        dir_y = end_dy / end_len
        # Normal vector (perpendicular)
        norm_x = -end_dy / end_len
        norm_y = end_dx / end_len

        # Extend forward by CHANNEL_EXTENSION
        ext_x = end_pt[0] + dir_x * CHANNEL_EXTENSION
        ext_y = end_pt[1] + dir_y * CHANNEL_EXTENSION

        # Add tongue points at the end
        tongue_end_left = [ext_x + norm_x * half_inner, ext_y + norm_y * half_inner]
        tongue_end_right = [ext_x - norm_x * half_inner, ext_y - norm_y * half_inner]
        inner_left.push(tongue_end_left)
        inner_right.push(tongue_end_right)
      end
    end

    {
      inner_channel: inner_left + inner_right.reverse,
      outer_boundary: outer_left + outer_right.reverse,
      left_wall: outer_left + inner_left.reverse,
      right_wall: outer_right + inner_right.reverse
    }
  end

  def area
    @width * @height
  end

  def can_rotate_90?
    # Only allow 90° rotation if grain tolerance permits
    # For now, allow it if the grain angle is close to 45°
    (@grain_angle.abs - 45).abs < 50
  end
end

#===============================================================================
# SHELF BIN PACKING ALGORITHM
#===============================================================================

class ShelfPacker
  def initialize(board_width, board_length, spacing, margin)
    @board_width = board_width
    @board_length = board_length
    @spacing = spacing
    @margin = margin
    @shelves = []  # Each shelf: { y: start_y, height: max_height, items: [] }
  end

  def pack(pieces)
    # Sort by height descending for better packing
    sorted = pieces.sort_by { |p| -p.height }

    sorted.each do |piece|
      placed = false

      # Try to place in existing shelf
      @shelves.each do |shelf|
        if fits_in_shelf?(piece, shelf)
          place_in_shelf(piece, shelf)
          placed = true
          break
        end
      end

      # Create new shelf if needed
      unless placed
        new_shelf = create_shelf(piece)
        if new_shelf
          place_in_shelf(piece, new_shelf)
          @shelves << new_shelf
        else
          puts "WARNING: Piece #{piece.piece_num} doesn't fit!"
        end
      end
    end

    pieces
  end

  def total_height
    return @margin if @shelves.empty?
    @shelves.last[:y] + @shelves.last[:height] + @margin
  end

  def total_width
    @board_width
  end

  private

  def fits_in_shelf?(piece, shelf)
    # Check if piece fits in remaining shelf width
    shelf_end_x = shelf[:items].empty? ? @margin : shelf[:items].last[:x] + shelf[:items].last[:width] + @spacing
    remaining_width = @board_width - @margin - shelf_end_x

    piece.width <= remaining_width && piece.height <= shelf[:height] + @spacing
  end

  def place_in_shelf(piece, shelf)
    x = shelf[:items].empty? ? @margin : shelf[:items].last[:x] + shelf[:items].last[:width] + @spacing
    piece.x = x
    piece.y = shelf[:y]
    shelf[:items] << { x: x, width: piece.width, piece: piece }
    shelf[:height] = [shelf[:height], piece.height].max
  end

  def create_shelf(piece)
    y = @shelves.empty? ? @margin : @shelves.last[:y] + @shelves.last[:height] + @spacing

    # Check if new shelf fits
    if y + piece.height + @margin > @board_length
      return nil
    end

    { y: y, height: piece.height, items: [] }
  end
end

#===============================================================================
# GUILLOTINE BIN PACKING (Better for irregular pieces)
#===============================================================================

class GuillotinePacker
  def initialize(board_width, board_length, spacing, margin)
    @board_width = board_width - 2 * margin
    @board_length = board_length - 2 * margin
    @spacing = spacing
    @margin = margin
    @free_rects = [{ x: margin, y: margin, w: @board_width, h: @board_length }]
  end

  def pack(pieces)
    # Sort by area descending (largest first)
    sorted = pieces.sort_by { |p| -p.area }

    sorted.each do |piece|
      best_rect = nil
      best_idx = nil
      best_score = Float::INFINITY
      rotate_90 = false

      # Find best fitting rectangle
      @free_rects.each_with_index do |rect, idx|
        # Try normal orientation
        if piece.width + @spacing <= rect[:w] && piece.height + @spacing <= rect[:h]
          score = rect[:w] * rect[:h] - piece.width * piece.height
          if score < best_score
            best_score = score
            best_rect = rect
            best_idx = idx
            rotate_90 = false
          end
        end

        # Try 90° rotation if allowed
        if piece.can_rotate_90? && piece.height + @spacing <= rect[:w] && piece.width + @spacing <= rect[:h]
          score = rect[:w] * rect[:h] - piece.width * piece.height
          if score < best_score
            best_score = score
            best_rect = rect
            best_idx = idx
            rotate_90 = true
          end
        end
      end

      if best_rect
        place_piece(piece, best_rect, best_idx, rotate_90)
      else
        puts "WARNING: Piece #{piece.piece_num} doesn't fit!"
      end
    end

    pieces
  end

  def total_height
    # Find the maximum Y extent of placed pieces
    max_y = @margin
    @free_rects.each do |rect|
      # Skip free rects, we want placed pieces
    end
    # This is tricky - we need to track placed pieces
    # For now, return board length minus largest remaining free rect at bottom
    @board_length + 2 * @margin
  end

  def total_width
    @board_width + 2 * @margin
  end

  private

  def place_piece(piece, rect, rect_idx, rotate_90)
    # Place piece at top-left of rectangle
    piece.x = rect[:x]
    piece.y = rect[:y]

    pw = rotate_90 ? piece.height : piece.width
    ph = rotate_90 ? piece.width : piece.height

    if rotate_90
      # Swap dimensions and rotate geometry
      piece.instance_variable_set(:@width, pw)
      piece.instance_variable_set(:@height, ph)
      rotate_geometry_90(piece)
    end

    # Remove this rectangle
    @free_rects.delete_at(rect_idx)

    # Split remaining space (guillotine cut)
    # Right remainder
    if rect[:w] - pw - @spacing > @spacing
      @free_rects << {
        x: rect[:x] + pw + @spacing,
        y: rect[:y],
        w: rect[:w] - pw - @spacing,
        h: rect[:h]
      }
    end

    # Bottom remainder
    if rect[:h] - ph - @spacing > @spacing
      @free_rects << {
        x: rect[:x],
        y: rect[:y] + ph + @spacing,
        w: pw,
        h: rect[:h] - ph - @spacing
      }
    end
  end

  def rotate_geometry_90(piece)
    # Rotate all geometry 90° clockwise
    rotate = ->(pts) {
      pts.map { |p| [p[1], -p[0] + piece.height] }
    }

    piece.instance_variable_set(:@inner_channel, rotate.call(piece.inner_channel))
    piece.instance_variable_set(:@left_wall, rotate.call(piece.left_wall))
    piece.instance_variable_set(:@right_wall, rotate.call(piece.right_wall))
  end
end

#===============================================================================
# SKYLINE BIN PACKING (Good balance of efficiency and simplicity)
#===============================================================================

class SkylinePacker
  def initialize(board_width, board_length, spacing, margin)
    @board_width = board_width
    @board_length = board_length
    @spacing = spacing
    @margin = margin
    @skyline = [{ x: margin, y: margin, width: board_width - 2 * margin }]
    @placed = []
  end

  def pack(pieces)
    # Sort by height descending for better packing
    sorted = pieces.sort_by { |p| -[p.height, p.width].max }

    sorted.each do |piece|
      best_pos = find_best_position(piece)

      if best_pos
        place_piece(piece, best_pos[:x], best_pos[:y], best_pos[:rotate])
      else
        puts "WARNING: Piece #{piece.piece_num} doesn't fit!"
      end
    end

    pieces
  end

  def total_height
    max_y = @margin
    @placed.each do |p|
      max_y = [max_y, p[:y] + p[:height]].max
    end
    max_y + @margin
  end

  def total_width
    @board_width
  end

  private

  def find_best_position(piece)
    best = nil
    best_waste = Float::INFINITY

    @skyline.each_with_index do |segment, idx|
      # Try normal orientation
      pos = try_position(piece, idx, false)
      if pos && pos[:waste] < best_waste
        best = pos
        best_waste = pos[:waste]
      end

      # Try 90° rotation if allowed
      if piece.can_rotate_90?
        pos = try_position(piece, idx, true)
        if pos && pos[:waste] < best_waste
          best = pos
          best_waste = pos[:waste]
        end
      end
    end

    best
  end

  def try_position(piece, segment_idx, rotate)
    segment = @skyline[segment_idx]

    pw = rotate ? piece.height : piece.width
    ph = rotate ? piece.width : piece.height

    # Check if piece fits horizontally
    return nil if segment[:x] + pw > @board_width - @margin

    # Find the maximum Y across all segments this piece would span
    max_y = segment[:y]
    remaining_width = pw
    current_idx = segment_idx

    while remaining_width > 0 && current_idx < @skyline.length
      seg = @skyline[current_idx]
      max_y = [max_y, seg[:y]].max
      remaining_width -= seg[:width]
      current_idx += 1
    end

    # Check if piece fits vertically
    return nil if max_y + ph + @spacing > @board_length - @margin

    # Calculate waste (empty space created)
    waste = (max_y - segment[:y]) * pw

    { x: segment[:x], y: max_y, rotate: rotate, waste: waste }
  end

  def place_piece(piece, x, y, rotate)
    pw = rotate ? piece.height : piece.width
    ph = rotate ? piece.width : piece.height

    if rotate
      piece.instance_variable_set(:@width, pw)
      piece.instance_variable_set(:@height, ph)
      rotate_geometry_90(piece)
    end

    piece.x = x
    piece.y = y

    @placed << { x: x, y: y, width: pw, height: ph }

    # Update skyline
    update_skyline(x, y + ph + @spacing, pw)
  end

  def update_skyline(x, new_y, width)
    # Find affected segments
    new_skyline = []
    remaining_width = width

    @skyline.each do |seg|
      if seg[:x] + seg[:width] <= x
        # Segment is entirely before our piece
        new_skyline << seg
      elsif seg[:x] >= x + width
        # Segment is entirely after our piece
        new_skyline << seg
      else
        # Segment overlaps with our piece
        # Add left portion if any
        if seg[:x] < x
          new_skyline << { x: seg[:x], y: seg[:y], width: x - seg[:x] }
        end

        # The overlapping part gets new height (handled after loop)

        # Add right portion if any
        if seg[:x] + seg[:width] > x + width
          new_skyline << { x: x + width, y: seg[:y], width: seg[:x] + seg[:width] - x - width }
        end
      end
    end

    # Add new segment for placed piece
    new_skyline << { x: x, y: new_y, width: width }

    # Sort and merge adjacent segments at same height
    @skyline = new_skyline.sort_by { |s| s[:x] }
    merge_skyline
  end

  def merge_skyline
    merged = []
    @skyline.each do |seg|
      if merged.empty?
        merged << seg
      elsif merged.last[:y] == seg[:y] && merged.last[:x] + merged.last[:width] == seg[:x]
        # Merge adjacent segments at same height
        merged.last[:width] += seg[:width]
      else
        merged << seg
      end
    end
    @skyline = merged
  end

  def rotate_geometry_90(piece)
    h = piece.height
    rotate = ->(pts) {
      pts.map { |p| [p[1], h - p[0]] }
    }

    piece.instance_variable_set(:@inner_channel, rotate.call(piece.inner_channel))
    piece.instance_variable_set(:@left_wall, rotate.call(piece.left_wall))
    piece.instance_variable_set(:@right_wall, rotate.call(piece.right_wall))
  end
end

#===============================================================================
# SVG GENERATOR
#===============================================================================

class LayoutSVGGenerator
  def initialize(pieces, board_width, board_height, margin)
    @pieces = pieces
    @board_width = board_width
    @board_height = board_height
    @margin = margin
  end

  def generate
    svg = <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <svg xmlns="http://www.w3.org/2000/svg"
           width="#{@board_width}in"
           height="#{@board_height.ceil}in"
           viewBox="0 0 #{@board_width} #{@board_height.ceil}">
      <style>
        .inner-channel { fill: #AAAAAA; stroke: none; }
        .sidewall { fill: #333333; stroke: none; }
        .label { font-family: Arial, sans-serif; font-weight: bold; fill: #333; }
        .grain-line { stroke: #8B4513; stroke-width: 0.02; opacity: 0.3; }
        .note { font-family: Arial, sans-serif; font-size: 0.2px; fill: #666; }
        .board-outline { fill: none; stroke: #000; stroke-width: 0.02; stroke-dasharray: 0.1,0.1; }
        .piece-bbox { fill: none; stroke: #0066FF; stroke-width: 0.01; opacity: 0.3; }
      </style>

      <!-- Background -->
      <rect width="100%" height="100%" fill="#FDF5E6" />

      <!-- Grid -->
      <defs>
        <pattern id="grid" width="1" height="1" patternUnits="userSpaceOnUse">
          <path d="M 1 0 L 0 0 0 1" fill="none" stroke="#DDD" stroke-width="0.02"/>
        </pattern>
        <pattern id="grain-pattern" width="0.5" height="0.5" patternUnits="userSpaceOnUse">
          <line x1="0" y1="0" x2="0" y2="0.5" stroke="#8B4513" stroke-width="0.01" opacity="0.15"/>
        </pattern>
      </defs>
      <rect x="0" y="0" width="#{@board_width}" height="#{@board_height.ceil}" fill="url(#grid)"/>

      <!-- Board grain direction indicator -->
      <rect x="#{@margin}" y="#{@margin}" width="#{@board_width - 2*@margin}" height="#{@board_height.ceil - 2*@margin}" fill="url(#grain-pattern)" class="board-outline"/>

      <!-- Pieces -->
    SVG

    total_area = 0

    @pieces.each do |piece|
      next unless piece.x && piece.y && piece.inner_channel

      total_area += piece.width * piece.height

      # Inner channel
      svg += path_element(piece.inner_channel, piece.x, piece.y, "inner-channel")

      # Sidewalls
      svg += path_element(piece.left_wall, piece.x, piece.y, "sidewall")
      svg += path_element(piece.right_wall, piece.x, piece.y, "sidewall")

      # Bounding box (for debugging)
      svg += %(<rect x="#{piece.x.round(3)}" y="#{piece.y.round(3)}" width="#{piece.width.round(3)}" height="#{piece.height.round(3)}" class="piece-bbox" />\n)

      # Label
      label_x = piece.x + piece.width / 2
      label_y = piece.y - 0.3
      svg += %(<text x="#{label_x.round(3)}" y="#{label_y.round(3)}" class="label" style="font-size: 0.4px;" text-anchor="middle">#{piece.piece_num}</text>\n)

      # Grain direction indicator (small arrow)
      arrow_x = piece.x + piece.width / 2
      arrow_y = piece.y + 0.5
      svg += %(<line x1="#{arrow_x.round(3)}" y1="#{(arrow_y).round(3)}" x2="#{arrow_x.round(3)}" y2="#{(arrow_y + 0.8).round(3)}" stroke="#8B4513" stroke-width="0.05" marker-end="url(#arrow)"/>\n)
    end

    # Arrow marker definition
    svg += <<~ARROW
      <defs>
        <marker id="arrow" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="0.3" markerHeight="0.3" orient="auto">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="#8B4513"/>
        </marker>
      </defs>
    ARROW

    # Stats
    board_area = @board_width * @board_height
    efficiency = (total_area / board_area * 100).round(1)

    svg += %(<text x="#{@margin}" y="#{@board_height.ceil - 0.3}" class="note">)
    svg += %(Board: #{@board_width}" x #{@board_height.ceil}" | )
    svg += %(Piece area: #{total_area.round(1)} sq in | )
    svg += %(Efficiency: #{efficiency}% | )
    svg += %(Grain: vertical (↓)</text>\n)

    svg += "</svg>\n"
    svg
  end

  private

  def path_element(points, offset_x, offset_y, css_class)
    return "" if points.nil? || points.length < 3

    translated = points.map { |p| [p[0] + offset_x, p[1] + offset_y] }

    d = "M #{translated.first[0].round(3)} #{translated.first[1].round(3)}"
    translated[1..-1].each do |pt|
      d += " L #{pt[0].round(3)} #{pt[1].round(3)}"
    end
    d += " Z"

    %(<path d="#{d}" class="#{css_class}" />\n)
  end
end

#===============================================================================
# MULTIBOARD SVG GENERATOR
#===============================================================================

class MultiboardSVGGenerator
  def initialize(pieces, board_layouts, svg_width, svg_height, margin)
    @pieces = pieces
    @board_layouts = board_layouts
    @svg_width = svg_width
    @svg_height = svg_height
    @margin = margin
  end

  def generate(cnc_friendly: false)
    # Round dimensions for cleaner output
    width = @svg_width.round(3)
    height = @svg_height.round(3)

    # Calibration square position (bottom-left, grid-aligned)
    cal_y = (height - 1).floor

    if cnc_friendly
      # CNC-friendly version: no backgrounds, just pieces and calibration square
      svg = <<~SVG
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg"
             width="#{width}in"
             height="#{height}in"
             viewBox="0 0 #{width} #{height}">
        <style>
          .outer-boundary { fill: #333333; stroke: none; }
          .inner-channel { fill: #AAAAAA; stroke: none; }
        </style>

        <!-- 1" x 1" Calibration Square (bottom-left, grid-aligned) -->
        <rect x="0" y="#{cal_y}" width="1" height="1" fill="#000000"/>
      SVG
    else
      # Full version with backgrounds, grid, labels
      svg = <<~SVG
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg"
             width="#{width}in"
             height="#{height}in"
             viewBox="0 0 #{width} #{height}">
        <style>
          .outer-boundary { fill: #333333; stroke: none; }
          .inner-channel { fill: #AAAAAA; stroke: none; }
          .label { font-family: Arial, sans-serif; font-weight: bold; fill: #333; }
          .board-label { font-family: Arial, sans-serif; font-size: 0.35px; fill: #666; }
          .grain-arrow { stroke: #8B4513; stroke-width: 0.04; fill: none; }
          .note { font-family: Arial, sans-serif; font-size: 0.2px; fill: #666; }
          .board { fill: #DEB887; stroke: #8B4513; stroke-width: 0.03; }
          .glueup { fill: #D2B48C; stroke: #8B4513; stroke-width: 0.03; stroke-dasharray: 0.1,0.05; }
          .piece-bbox { fill: none; stroke: #0066FF; stroke-width: 0.01; opacity: 0.3; }
        </style>

        <!-- Background (explicit dimensions, not 100%) -->
        <rect x="0" y="0" width="#{width}" height="#{height}" fill="#F5F5DC" />

        <!-- Grid -->
        <defs>
          <pattern id="grid" width="1" height="1" patternUnits="userSpaceOnUse">
            <path d="M 1 0 L 0 0 0 1" fill="none" stroke="#DDD" stroke-width="0.015"/>
          </pattern>
          <pattern id="grain-lines" width="0.3" height="0.3" patternUnits="userSpaceOnUse">
            <line x1="0" y1="0" x2="0" y2="0.3" stroke="#A0522D" stroke-width="0.01" opacity="0.2"/>
          </pattern>
          <marker id="arrow" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="0.4" markerHeight="0.4" orient="auto">
            <path d="M 0 0 L 10 5 L 0 10 z" fill="#8B4513"/>
          </marker>
        </defs>
        <rect x="0" y="0" width="#{width}" height="#{height}" fill="url(#grid)"/>

        <!-- 1" x 1" Calibration Square (bottom-left, grid-aligned) -->
        <rect x="0" y="#{cal_y}" width="1" height="1" fill="#000000"/>
      SVG
    end

    # Draw each board (skip board backgrounds for CNC-friendly version)
    @board_layouts.each do |board|
      bx = board[:x] || @margin

      unless cnc_friendly
        css_class = board[:type] == :glueup ? 'glueup' : 'board'

        # Board background with grain texture
        svg += %(<rect x="#{bx}" y="#{board[:y]}" width="#{board[:width]}" height="#{board[:length]}" class="#{css_class}" fill="url(#grain-lines)"/>\n)

        # Board outline
        svg += %(<rect x="#{bx}" y="#{board[:y]}" width="#{board[:width]}" height="#{board[:length]}" class="#{css_class}"/>\n)

        # Board label (above the board with more padding)
        svg += %(<text x="#{bx + board[:width] / 2}" y="#{board[:y] - 0.5}" class="board-label" text-anchor="middle">#{board[:label]}</text>\n)
      end
    end

    # Draw pieces
    @pieces.each do |piece|
      next unless piece.x && piece.y && piece.inner_channel

      # Apply 180° rotation if needed (flips the piece vertically)
      rotated = piece.rotated_180

      # Group all piece components together
      piece_id = "piece-#{piece.piece_num}"
      svg += %(<g id="#{piece_id}">\n)

      # Outer boundary (full piece outline including sidewalls)
      svg += path_element_rotated(piece.outer_boundary, piece.x, piece.y, piece.width, piece.height, rotated, "outer-boundary")

      # Inner channel (the track groove)
      svg += path_element_rotated(piece.inner_channel, piece.x, piece.y, piece.width, piece.height, rotated, "inner-channel")

      svg += %(</g>\n)

      # Piece labels (skip for CNC-friendly version)
      unless cnc_friendly
        # Find which board this piece is on
        piece_board = @board_layouts.find { |b| piece.x >= b[:x] && piece.x < b[:x] + b[:width] + 1 }
        next unless piece_board

        # Label position: below the board, horizontally centered on piece
        label_x = piece.x + piece.width / 2
        label_y = piece_board[:y] + piece_board[:length] + 0.4  # Below the board

        # Piece number (add "ᴿ" suffix if rotated)
        label_text = piece.piece_num.to_s + (rotated ? "ᴿ" : "")

        # Grain direction indicator: ↑ for normal, ↓ for rotated
        grain_indicator = rotated ? "↓" : "↑"

        svg += %(<text x="#{label_x.round(3)}" y="#{label_y.round(3)}" class="label" style="font-size: 0.4px;" text-anchor="middle" dominant-baseline="middle">#{label_text} #{grain_indicator}</text>\n)
      end
    end

    svg += "</svg>\n"
    svg
  end

  private

  def path_element_rotated(points, offset_x, offset_y, piece_width, piece_height, rotated, css_class)
    return "" if points.nil? || points.length < 3

    if rotated
      # 180° rotation: flip both x and y around center
      translated = points.map do |p|
        new_x = piece_width - p[0]
        new_y = piece_height - p[1]
        [new_x + offset_x, new_y + offset_y]
      end
    else
      translated = points.map { |p| [p[0] + offset_x, p[1] + offset_y] }
    end

    d = "M #{translated.first[0].round(3)} #{translated.first[1].round(3)}"
    translated[1..-1].each do |pt|
      d += " L #{pt[0].round(3)} #{pt[1].round(3)}"
    end
    d += " Z"

    %(<path d="#{d}" class="#{css_class}" />\n)
  end
end

#===============================================================================
# MAIN
#===============================================================================

puts "="*60
puts "PIECE LAYOUT OPTIMIZER"
puts "="*60
puts ""

# Run the track generator to get piece data
visualizer = SplitVisualizer.new(INPUT_FILE, OUTPUT_FILE)
piece_data_raw = visualizer.generate

puts ""
puts "Processing #{piece_data_raw.length} pieces..."
puts ""

# Convert to PieceData objects
pieces = piece_data_raw.map do |pd|
  PieceData.new(pd, INNER_TRACK_WIDTH_IN, SIDEWALL_THICKNESS_IN)
end.compact

# Filter out pieces that didn't process correctly
pieces = pieces.select { |p| p.inner_channel && p.inner_channel.length > 0 }

puts "Piece dimensions with grain angles:"
puts "-" * 50
pieces.sort_by { |p| p.piece_num }.each do |p|
  puts "  Piece #{p.piece_num.to_s.rjust(2)}: #{p.width.round(2).to_s.rjust(6)}\" x #{p.height.round(2).to_s.ljust(6)}\" (grain: #{GRAIN_OVERRIDES[p.piece_num] || 0}°)"
end
puts ""

# Try different packing algorithms
puts "Testing packing algorithms..."
puts ""

# Best-fit decreasing height bin packing with gap filling
def optimized_strip_pack(pieces, board_width, spacing, margin)
  # Sort by height descending - tallest pieces create the row heights
  sorted = pieces.sort_by { |p| -p.height }

  # Track rows with their remaining space and height
  rows = []

  sorted.each do |piece|
    placed = false

    # First, try to fit in an existing row
    # Prefer rows where the piece fits best (least wasted vertical space)
    best_row = nil
    best_waste = Float::INFINITY

    rows.each do |row|
      # Check if piece fits horizontally in remaining space
      next unless row[:remaining_x] + piece.width + spacing <= board_width - margin

      # Calculate vertical waste if we place here
      waste = row[:height] - piece.height
      next if waste < -spacing  # Piece too tall for this row

      if waste >= 0 && waste < best_waste
        best_waste = waste
        best_row = row
      end
    end

    if best_row
      piece.x = best_row[:remaining_x]
      piece.y = best_row[:y]
      best_row[:remaining_x] += piece.width + spacing
      best_row[:pieces] << piece
      placed = true
    end

    unless placed
      # Create new row
      y = rows.empty? ? margin + 0.6 : rows.last[:y] + rows.last[:height] + spacing
      piece.x = margin
      piece.y = y
      rows << {
        y: y,
        height: piece.height,
        pieces: [piece],
        remaining_x: margin + piece.width + spacing
      }
    end
  end

  # Calculate total height
  rows.empty? ? margin : rows.last[:y] + rows.last[:height] + margin
end

# Try to nest short pieces under tall ones in the same row
def nested_strip_pack(pieces, board_width, spacing, margin)
  sorted = pieces.sort_by { |p| -p.height }

  rows = []

  sorted.each do |piece|
    placed = false

    # Try to fit in existing row
    rows.each do |row|
      next unless row[:remaining_x] + piece.width + spacing <= board_width - margin

      # If piece is shorter than row, check if we can stack it
      if piece.height <= row[:height]
        # Try to find a gap above placed pieces where this could fit
        # For now, just place at end of row
        piece.x = row[:remaining_x]
        piece.y = row[:y]
        row[:remaining_x] += piece.width + spacing
        row[:pieces] << piece
        placed = true
        break
      end
    end

    unless placed
      y = rows.empty? ? margin + 0.6 : rows.last[:y] + rows.last[:height] + spacing
      piece.x = margin
      piece.y = y
      rows << {
        y: y,
        height: piece.height,
        pieces: [piece],
        remaining_x: margin + piece.width + spacing
      }
    end
  end

  rows.empty? ? margin : rows.last[:y] + rows.last[:height] + margin
end

# Separate pieces by board type
# Account for margins when determining fit
usable_wide_board = WIDE_BOARD_WIDTH - 2 * BOARD_MARGIN  # ~6" usable on 7" board

narrow_pieces = pieces.select { |p|
  (p.width <= usable_wide_board || FORCE_SINGLE_BOARD.include?(p.piece_num)) &&
  !SOLO_PANEL_PIECES.include?(p.piece_num)
}
wide_pieces = pieces.select { |p|
  (p.width > usable_wide_board && !FORCE_SINGLE_BOARD.include?(p.piece_num)) ||
  SOLO_PANEL_PIECES.include?(p.piece_num)
}

puts ""
puts "Board requirements:"
puts "  Fit on single boards (up to #{WIDE_BOARD_WIDTH}\" wide):"
narrow_pieces.sort_by { |p| -p.width }.each do |p|
  board_type = p.width <= 4.0 ? "5\"" : (p.width <= 5.0 ? "6\"" : "7\"")
  puts "    Piece #{p.piece_num}: #{p.width.round(2)}\" wide -> needs #{board_type} board"
end
puts "  Need glue-up panels:"
wide_pieces.each do |p|
  puts "    Piece #{p.piece_num}: #{p.width.round(2)}\" wide"
end
puts ""

# Pack pieces with side-by-side nesting for straight pieces
def pack_onto_boards_nested(pieces, board_length, board_width, spacing, margin)
  boards = []

  # First, handle special nesting pairs from configuration
  paired = []
  used_piece_nums = Set.new

  NESTING_PAIRS.each do |pair_nums, config|
    p1 = pieces.find { |p| p.piece_num == pair_nums[0] }
    p2 = pieces.find { |p| p.piece_num == pair_nums[1] }

    next unless p1 && p2

    used_piece_nums << pair_nums[0]
    used_piece_nums << pair_nums[1]

    paired << {
      pieces: [p1, p2],
      type: :manual,
      config: config
    }
  end

  # Separate remaining pieces
  remaining_pieces = pieces.reject { |p| used_piece_nums.include?(p.piece_num) }

  # Solo board pieces get their own dedicated boards (no sharing)
  solo_pieces = remaining_pieces.select { |p| SOLO_BOARD_PIECES.include?(p.piece_num) }
  remaining_pieces = remaining_pieces.reject { |p| SOLO_BOARD_PIECES.include?(p.piece_num) }

  solo_pieces.each do |p|
    paired << { pieces: [p], type: :solo, config: {} }
  end

  straight_pieces = remaining_pieces.select { |p| p.width <= 3.0 }
  other_pieces = remaining_pieces.select { |p| p.width > 3.0 }

  # Sort straight pieces by height descending
  straight_pieces.sort_by! { |p| -p.height }

  # Try to pair up straight pieces side-by-side (generic pairing)
  used = Set.new

  straight_pieces.each_with_index do |p1, i|
    next if used.include?(i)

    best_match = nil
    best_idx = nil

    straight_pieces.each_with_index do |p2, j|
      next if i == j || used.include?(j)

      combined_width = p1.width + p2.width + spacing
      next if combined_width > board_width - 2 * margin

      height_diff = (p1.height - p2.height).abs
      if best_match.nil? || height_diff < (p1.height - best_match.height).abs
        best_match = p2
        best_idx = j
      end
    end

    if best_match
      paired << { pieces: [p1, best_match], type: :side_by_side, config: {} }
      used << i
      used << best_idx
    else
      paired << { pieces: [p1], type: :single, config: {} }
      used << i
    end
  end

  # Add other pieces as singles
  other_pieces.each do |p|
    paired << { pieces: [p], type: :single, config: {} }
  end

  # Now pack the paired/single groups onto boards
  paired.sort_by! { |g| -g[:pieces].map(&:height).max }

  paired.each do |group|
    placed = false
    config = group[:config] || {}

    # Calculate group dimensions based on nesting config
    if group[:type] == :manual && group[:pieces].length == 2
      # Manual nesting: calculate bounds based on explicit positioning
      p1, p2 = group[:pieces]
      p1_x = config[:p1_x] || 0
      p1_y = config[:p1_y] || 0
      p2_x = config[:p2_x] || (p1.width + PIECE_SPACING)
      p2_y = config[:p2_y] || 0

      # Group width is the rightmost extent
      group_width = [p1_x + p1.width, p2_x + p2.width].max
      # Group height accounts for y offset
      group_height = [p1_y + p1.height, p2_y + p2.height].max
    elsif group[:pieces].length > 1
      group_width = group[:pieces].sum(&:width) + (group[:pieces].length - 1) * spacing
      group_height = group[:pieces].map(&:height).max
    else
      group_width = group[:pieces].first.width
      group_height = group[:pieces].first.height
    end

    # Solo pieces always get their own board
    if group[:type] == :solo
      piece = group[:pieces].first
      piece.board_offset = margin
      piece.x_in_group = 0
      piece.rotated_180 = false

      boards << {
        pieces: group[:pieces].dup,
        used_length: margin + group_height + spacing,
        max_width: group_width,
        locked: true  # Prevent other pieces from being added
      }
      next
    end

    # Try to fit on existing board (skip locked boards)
    boards.each do |board|
      next if board[:locked]

      remaining = board_length - board[:used_length] - margin
      if group_height + spacing <= remaining
        board_used_width = board[:max_width] || 0

        # Place the group based on nesting type
        if group[:type] == :manual && group[:pieces].length == 2
          # Manual nesting with explicit positioning
          p1, p2 = group[:pieces]
          p1_rotate = config[:p1_rotate] || 0
          p1_x = config[:p1_x] || 0
          p1_y = config[:p1_y] || 0
          p2_rotate = config[:p2_rotate] || 0
          p2_x = config[:p2_x] || (p1.width + PIECE_SPACING)
          p2_y = config[:p2_y] || 0

          p1.board_offset = board[:used_length] + p1_y
          p1.x_in_group = p1_x
          p1.rotated_180 = (p1_rotate == 180)

          p2.board_offset = board[:used_length] + p2_y
          p2.x_in_group = p2_x
          p2.rotated_180 = (p2_rotate == 180)
        elsif group[:type] == :side_by_side
          x_offset = 0
          group[:pieces].each_with_index do |piece, idx|
            piece.board_offset = board[:used_length]
            piece.x_in_group = x_offset
            piece.rotated_180 = (idx == 1)
            x_offset += piece.width + spacing
          end
        else
          piece = group[:pieces].first
          piece.board_offset = board[:used_length]
          piece.x_in_group = 0
          piece.rotated_180 = false
        end

        board[:pieces].concat(group[:pieces])
        board[:used_length] += group_height + spacing
        board[:max_width] = [board[:max_width] || 0, group_width].max
        placed = true
        break
      end
    end

    unless placed
      # Create new board - handle nesting types
      if group[:type] == :manual && group[:pieces].length == 2
        # Manual nesting with explicit positioning
        p1, p2 = group[:pieces]
        p1_rotate = config[:p1_rotate] || 0
        p1_x = config[:p1_x] || 0
        p1_y = config[:p1_y] || 0
        p2_rotate = config[:p2_rotate] || 0
        p2_x = config[:p2_x] || (p1.width + PIECE_SPACING)
        p2_y = config[:p2_y] || 0

        p1.board_offset = margin + p1_y
        p1.x_in_group = p1_x
        p1.rotated_180 = (p1_rotate == 180)

        p2.board_offset = margin + p2_y
        p2.x_in_group = p2_x
        p2.rotated_180 = (p2_rotate == 180)
      elsif group[:type] == :side_by_side
        x_offset = 0
        group[:pieces].each_with_index do |piece, idx|
          piece.board_offset = margin
          piece.x_in_group = x_offset
          piece.rotated_180 = (idx == 1)
          x_offset += piece.width + spacing
        end
      else
        piece = group[:pieces].first
        piece.board_offset = margin
        piece.x_in_group = 0
        piece.rotated_180 = false
      end

      boards << {
        pieces: group[:pieces].dup,
        used_length: margin + group_height + spacing,
        max_width: group_width
      }
    end
  end

  boards
end

# Simple pack (fallback)
def pack_onto_boards(pieces, board_length, board_width, spacing, margin)
  boards = []
  sorted = pieces.sort_by { |p| -p.height }

  sorted.each do |piece|
    placed = false
    next if piece.width > board_width - 2 * margin

    boards.each do |board|
      remaining = board_length - board[:used_length] - margin
      if piece.height + spacing <= remaining
        piece.board_offset = board[:used_length]
        piece.x_in_group = 0
        piece.rotated_180 = false
        board[:pieces] << piece
        board[:used_length] += piece.height + spacing
        placed = true
        break
      end
    end

    unless placed
      piece.board_offset = margin
      piece.x_in_group = 0
      piece.rotated_180 = false
      boards << {
        pieces: [piece],
        used_length: margin + piece.height + spacing
      }
    end
  end

  boards
end

# Pack narrow pieces onto boards with side-by-side nesting
narrow_boards = pack_onto_boards_nested(narrow_pieces, STANDARD_BOARD_LENGTH, WIDE_BOARD_WIDTH, PIECE_SPACING, BOARD_MARGIN)

puts "Single boards (#{STANDARD_BOARD_LENGTH}\" long, up to #{WIDE_BOARD_WIDTH}\" wide):"
narrow_boards.each_with_index do |board, idx|
  # Use group width for side-by-side pieces, otherwise max piece width
  group_width = board[:max_width] || board[:pieces].map { |p| p.width }.max
  board_width = group_width <= 4.4 ? 5.0 : (group_width <= 5.4 ? 6.0 : 7.0)
  pieces_str = board[:pieces].map { |p| "##{p.piece_num} (#{p.width.round(1)}\"×#{p.height.round(1)}\")" }.join(', ')
  efficiency = (board[:used_length] / STANDARD_BOARD_LENGTH * 100).round(1)
  side_by_side = board[:pieces].length > 1 && board[:pieces].map(&:board_offset).uniq.length < board[:pieces].length
  layout_note = side_by_side ? " [side-by-side]" : ""
  puts "  Board #{idx + 1} (#{board_width.round(0)}\"×36\"): #{pieces_str}#{layout_note}"
  puts "    Length used: #{board[:used_length].round(1)}\"/#{STANDARD_BOARD_LENGTH}\" (#{efficiency}%)"
end

# Pack wide pieces onto glue-up panels - each gets its own panel
glueup_boards = []
wide_pieces.sort_by { |p| -p.height }.each do |piece|
  piece.board_offset = BOARD_MARGIN
  piece.x_in_group = 0
  piece.rotated_180 = false
  glueup_boards << {
    pieces: [piece],
    used_length: BOARD_MARGIN + piece.height + PIECE_SPACING,
    max_width: piece.width
  }
end

if glueup_boards.any?
  puts ""
  puts "Glue-up panels (#{STANDARD_BOARD_LENGTH}\" x #{GLUEUP_PANEL_WIDTH}\"):"
  glueup_boards.each_with_index do |board, idx|
    pieces_str = board[:pieces].map { |p| "#{p.piece_num} (#{p.width.round(1)}\" x #{p.height.round(1)}\")" }.join(', ')
    puts "  Panel #{idx + 1}: #{pieces_str}"
  end
end

# Generate SVG showing all boards SIDE BY SIDE (horizontal layout)
total_boards = narrow_boards.length + glueup_boards.length

# Layout parameters
board_gap = 1.0           # Gap between boards
top_padding = 1.5         # Extra space at top for labels
bottom_padding = 2.5  # Extra space at bottom for labels and calibration square

# Position pieces and track board layouts for SVG
board_layouts = []
current_x = BOARD_MARGIN

# Single boards first (side by side)
max_board_length = 0
narrow_boards.each_with_index do |board, idx|
  # Calculate exact board width from pieces (no outer margin)
  group_width = board[:max_width] || board[:pieces].map { |p| p.width }.max
  board_width = group_width  # Exact piece width, no margin

  # Calculate exact board length from pieces (no outer margin)
  # Find the max extent of all pieces on this board
  max_piece_extent = board[:pieces].map { |p| (p.board_offset - BOARD_MARGIN) + p.height }.max
  board_length = max_piece_extent  # Exact piece extent, no margin

  board[:pieces].each do |piece|
    # Position pieces at edge of board (no outer margin)
    x_offset = piece.x_in_group || 0
    piece.x = current_x + x_offset
    piece.y = top_padding + (piece.board_offset - BOARD_MARGIN)  # Remove the margin that was added in packing
  end

  # Create label with fractional dimensions
  width_frac = inches_to_fraction(board_width)
  length_frac = inches_to_fraction(board_length)

  board_layouts << {
    type: :standard,
    x: current_x,
    y: top_padding,
    width: board_width,
    length: board_length,
    label: "#{width_frac}\" × #{length_frac}\""
  }
  max_board_length = [max_board_length, board_length].max
  current_x += board_width + board_gap
end

# Glue-up panels (continue side by side)
glueup_boards.each_with_index do |board, idx|
  # Calculate exact panel dimensions (no outer margin)
  piece = board[:pieces].first
  panel_width = piece.width
  panel_length = piece.height

  piece.x = current_x
  piece.y = top_padding

  # Create label with fractional dimensions
  width_frac = inches_to_fraction(panel_width)
  length_frac = inches_to_fraction(panel_length)

  board_layouts << {
    type: :glueup,
    x: current_x,
    y: top_padding,
    width: panel_width,
    length: panel_length,
    label: "#{width_frac}\" × #{length_frac}\""
  }
  max_board_length = [max_board_length, panel_length].max
  current_x += panel_width + board_gap
end

svg_width = current_x + BOARD_MARGIN
total_height = top_padding + max_board_length + bottom_padding

# Calculate totals with actual board dimensions
total_standard_area = 0
board_summary = []
board_layouts.select { |b| b[:type] == :standard }.each do |board|
  area = board[:width] * board[:length]
  total_standard_area += area
  board_summary << "#{inches_to_fraction(board[:width])}\" × #{inches_to_fraction(board[:length])}\""
end

total_glueup_area = 0
board_layouts.select { |b| b[:type] == :glueup }.each do |board|
  total_glueup_area += board[:width] * board[:length]
end
# Calculate actual piece area from outer_boundary polygon (not bounding box)
total_piece_area = pieces.sum { |p| polygon_area(p.outer_boundary) }
total_area = total_standard_area + total_glueup_area
efficiency = (total_piece_area / total_area * 100).round(1)

panel_summary = board_layouts.select { |b| b[:type] == :glueup }.map { |b| "#{inches_to_fraction(b[:width])}\" × #{inches_to_fraction(b[:length])}\"" }

# Board foot calculations (1 board foot = 12" × 12" × 1" = 144 cubic inches)
# Since we're using 1" thick stock (4/4), board feet = sq in / 144
board_feet_standard = total_standard_area / 144.0
board_feet_glueup = total_glueup_area / 144.0
board_feet_total = total_area / 144.0

puts ""
puts "MATERIAL SUMMARY:"
puts "  Single boards:   #{narrow_boards.length} boards = #{total_standard_area.round(0)} sq in"
board_summary.each { |b| puts "    #{b}" }
puts "  Glue-up panels:  #{glueup_boards.length} panels = #{total_glueup_area.round(0)} sq in"
panel_summary.each { |p| puts "    #{p}" }
puts "  Total material:  #{total_area.round(0)} sq in"
puts "  Piece area:      #{total_piece_area.round(0)} sq in"
puts "  Efficiency:      #{efficiency}%"
puts ""
puts "BOARD FEET (4/4 stock, 1\" thick):"
puts "  Single boards:   #{board_feet_standard.round(2)} bf"
puts "  Glue-up panels:  #{board_feet_glueup.round(2)} bf"
puts "  Total needed:    #{board_feet_total.round(2)} bf"
puts "  (Add 15-20% for waste/defects: #{(board_feet_total * 1.2).round(2)} bf recommended)"

# Generate SVG with board layout visualization
generator = MultiboardSVGGenerator.new(pieces, board_layouts, svg_width, total_height, BOARD_MARGIN)

# Full version with backgrounds, grid, labels
svg = generator.generate
File.write(PIECES_LAYED_OUT_FILE, svg)
puts ""
puts "Generated #{PIECES_LAYED_OUT_FILE}"

# CNC-friendly version (no backgrounds, just pieces and calibration square)
svg_cnc = generator.generate(cnc_friendly: true)
File.write(PIECES_LAYED_OUT_EASEL_FILE, svg_cnc)
puts "Generated #{PIECES_LAYED_OUT_EASEL_FILE}"
puts ""

# Open in Cursor
system("cursor", PIECES_LAYED_OUT_FILE)
