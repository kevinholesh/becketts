#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Piece Generator for CNC cutting track curve samples
# Generates arc channels at various radii and track widths
# Edit the constants below to customize the test pieces

# Test parameters
RADII = [3.5, 4.5, 5.5, 7.0]  # inches, centerline radius
TRACK_WIDTHS = [1.75, 1.85, 1.95, 2.05]  # inches, inner channel width
CUT_DEPTH = 0.375  # 3/8 inch
ARC_DEGREES = 180  # degrees of arc (full 180° turn)

# Layout parameters
PADDING = 0.25  # inches between pieces
MIN_GAP = 0.15  # minimum gap between nested arcs for router bit

class TestPieceGenerator
  attr_reader :total_width, :total_height

  def initialize
    @pieces = []
    generate_test_pieces
    calculate_layout
  end

  def generate_test_pieces
    RADII.each do |radius|
      TRACK_WIDTHS.each do |width|
        @pieces << {
          radius: radius,
          width: width,
          inner_r: radius - width / 2.0,
          outer_r: radius + width / 2.0
        }
      end
    end
  end

  def calculate_layout
    # For 180° arcs, organize by width columns and nest radii that fit
    # Arc from 90° to 270° spans from bottom (+r) to top (-r), bulging left
    @layout = []

    current_x = PADDING

    TRACK_WIDTHS.each do |width|
      pieces_at_width = @pieces.select { |p| p[:width] == width }.sort_by { |p| -p[:radius] }

      # Find which pieces can be nested together
      groups = []
      pieces_at_width.each do |piece|
        placed = false
        groups.each do |group|
          # Check if this piece can nest inside the smallest piece in the group
          smallest = group.min_by { |p| p[:radius] }
          gap = smallest[:inner_r] - piece[:outer_r]
          if gap >= MIN_GAP
            group << piece
            placed = true
            break
          end
        end
        groups << [piece] unless placed
      end

      # Layout each group in this column
      max_outer = pieces_at_width.first[:outer_r]
      col_center_x = current_x + max_outer

      current_y = PADDING + 0.4 + max_outer  # center Y for first group (0.4 for column label)

      groups.each do |group|
        largest = group.max_by { |p| p[:radius] }
        group.each do |piece|
          piece[:x] = col_center_x
          piece[:y] = current_y
          piece[:arc_bottom] = current_y + piece[:outer_r]
          @layout << piece
        end
        # Move down for next group (non-nested pieces)
        current_y += largest[:outer_r] * 2 + PADDING + 0.5
      end

      current_x += max_outer * 2 + PADDING
    end

    # Calculate total bounds
    @total_width = current_x + 2.0  # extra space for calibration square
    max_bottom = @layout.map { |p| p[:arc_bottom] }.max
    @total_height = max_bottom + 2.0  # space for labels and calibration square
  end

  def generate_svg
    svg = []
    svg << svg_header
    svg << svg_styles

    # Generate each test piece
    @layout.each do |piece|
      svg << generate_arc_channel(piece)
      svg << generate_label(piece)
    end

    # Add column labels (width for each column)
    svg << generate_column_labels

    # Add calibration square (1" × 1")
    svg << generate_calibration_square

    # Add cut depth note
    svg << %(<text x="#{PADDING}" y="#{@total_height - 0.05}" class="note">Cut depth: #{CUT_DEPTH}"</text>)

    svg << '</svg>'
    svg.join("\n")
  end

  private

  def svg_header
    # 1 SVG unit = 1 inch, matching main generator
    %(<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     width="#{@total_width}in"
     height="#{@total_height}in"
     viewBox="0 0 #{@total_width} #{@total_height}">)
  end

  def svg_styles
    %(<style>
  .channel { fill: #333333; stroke: none; }
  .label { font-family: Arial, sans-serif; font-size: 0.18px; fill: #333; }
  .column-label { font-family: Arial, sans-serif; font-size: 0.25px; fill: #000; font-weight: bold; }
  .note { font-family: Arial, sans-serif; font-size: 0.2px; fill: #666; }
  .calibration { fill: none; stroke: #000000; stroke-width: 0.02; }
  .calibration-label { font-family: Arial, sans-serif; font-size: 0.12px; fill: #000; }
</style>
<rect width="100%" height="100%" fill="white" />)
  end

  def generate_arc_channel(piece)
    cx = piece[:x]
    cy = piece[:y]
    inner_r = piece[:inner_r]
    outer_r = piece[:outer_r]

    # Arc from 90° to (90° + ARC_DEGREES) - curves from straight down to down-left
    start_angle = 90 * Math::PI / 180
    end_angle = (90 + ARC_DEGREES) * Math::PI / 180

    # Start and end points for outer arc
    outer_start_x = cx + outer_r * Math.cos(start_angle)
    outer_start_y = cy + outer_r * Math.sin(start_angle)
    outer_end_x = cx + outer_r * Math.cos(end_angle)
    outer_end_y = cy + outer_r * Math.sin(end_angle)

    # Start and end points for inner arc
    inner_start_x = cx + inner_r * Math.cos(start_angle)
    inner_start_y = cy + inner_r * Math.sin(start_angle)
    inner_end_x = cx + inner_r * Math.cos(end_angle)
    inner_end_y = cy + inner_r * Math.sin(end_angle)

    # large-arc-flag: 0 if arc < 180°, 1 if arc >= 180°
    large_arc = ARC_DEGREES >= 180 ? 1 : 0

    # Path: outer arc (clockwise), line to inner, inner arc (counter-clockwise), close
    path = "M #{fmt(outer_start_x)} #{fmt(outer_start_y)} "
    path += "A #{fmt(outer_r)} #{fmt(outer_r)} 0 #{large_arc} 1 #{fmt(outer_end_x)} #{fmt(outer_end_y)} "
    path += "L #{fmt(inner_end_x)} #{fmt(inner_end_y)} "
    path += "A #{fmt(inner_r)} #{fmt(inner_r)} 0 #{large_arc} 0 #{fmt(inner_start_x)} #{fmt(inner_start_y)} "
    path += "Z"

    %(<path d="#{path}" class="channel" />)
  end

  def generate_label(piece)
    # Position label outside the arc, to the right of the opening
    label_x = piece[:x] + 0.15
    label_y = piece[:y] + 0.06

    text = "R#{piece[:radius]}\""

    %(<text x="#{fmt(label_x)}" y="#{fmt(label_y)}" class="label">#{text}</text>)
  end

  def generate_column_labels
    # Add width labels at top of each column
    labels = []
    max_outer = RADII.max + TRACK_WIDTHS.max / 2.0
    current_x = PADDING

    TRACK_WIDTHS.each do |width|
      col_center_x = current_x + max_outer
      labels << %(<text x="#{fmt(col_center_x)}" y="#{fmt(PADDING + 0.25)}" class="column-label" text-anchor="middle">W=#{width}"</text>)
      current_x += max_outer * 2 + PADDING
    end

    labels.join("\n")
  end

  def generate_calibration_square
    # 1" × 1" calibration square in bottom-right corner
    square_x = @total_width - 1.5
    square_y = @total_height - 1.8

    <<~SVG
      <rect x="#{fmt(square_x)}" y="#{fmt(square_y)}" width="1" height="1" class="calibration" />
      <text x="#{fmt(square_x + 0.5)}" y="#{fmt(square_y - 0.1)}" class="calibration-label" text-anchor="middle">1" × 1"</text>
      <text x="#{fmt(square_x + 0.5)}" y="#{fmt(square_y + 1.2)}" class="calibration-label" text-anchor="middle">calibration</text>
    SVG
  end

  def fmt(num)
    format('%.4f', num)
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  generator = TestPieceGenerator.new
  svg_content = generator.generate_svg

  output_path = File.join(__dir__, 'test_pieces.svg')
  File.write(output_path, svg_content)

  puts "Generated: #{output_path}"
  puts "Sheet size: %.1f\" × %.1f\"" % [generator.total_width, generator.total_height]
  puts "Pieces: #{RADII.length * TRACK_WIDTHS.length} test arcs (#{ARC_DEGREES}° each)"
  puts "Radii: #{RADII.join(', ')} inches"
  puts "Widths: #{TRACK_WIDTHS.join(', ')} inches"
  puts "Cut depth: #{CUT_DEPTH} inches"


  puts ""
  print 'Opening in Cursor...'
  system("cursor", output_path)

end