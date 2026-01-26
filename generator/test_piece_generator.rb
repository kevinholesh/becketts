#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Piece Generator for CNC cutting track curve samples
# Generates arc channels at various radii and track widths
# Edit the constants below to customize the test pieces

# Test parameters
RADII = [2.5, 3.0, 3.5, 4.0, 4.5, 5.0]  # inches, centerline radius
TRACK_WIDTHS = [1.75, 1.85, 1.95, 2.05]  # inches, inner channel width
CUT_DEPTH = 0.375  # 3/8 inch
ARC_DEGREES = 180  # degrees of arc (full half turn)

# Layout parameters
PADDING = 0.5  # inches between pieces
MIN_GAP = 0.12  # minimum gap between nested arcs for router bit

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
    # For 180° arcs, arrange in a grid - each arc is outer_r wide × 2*outer_r tall
    # Arc from 90° to 270°: starts at bottom, curves left, ends at top
    @layout = []
    @column_positions = []

    max_outer = RADII.max + TRACK_WIDTHS.max / 2.0
    arc_height = max_outer * 2  # 180° arc spans full diameter vertically

    # Grid: 4 columns (widths) × 4 rows (radii)
    TRACK_WIDTHS.each_with_index do |width, col_idx|
      col_x = PADDING + col_idx * (max_outer + PADDING) + max_outer

      RADII.sort.reverse.each_with_index do |radius, row_idx|
        piece = @pieces.find { |p| p[:width] == width && p[:radius] == radius }
        # Center Y for each row - arc extends outer_r above and below center
        center_y = PADDING + 0.5 + max_outer + row_idx * (arc_height + PADDING)

        piece[:x] = col_x
        piece[:y] = center_y
        piece[:arc_bottom] = center_y + piece[:outer_r]
        @layout << piece
      end

      @column_positions << { x: col_x, y: PADDING + 0.2, width: width }
    end

    # Calculate total bounds
    @total_width = PADDING + TRACK_WIDTHS.size * (max_outer + PADDING) + 1.3
    @total_height = PADDING + 0.5 + RADII.size * (arc_height + PADDING) + 1.0
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
    # Position label in the negative space inside the arc (center of the "rainbow")
    label_x = piece[:x] - piece[:inner_r] * 0.5
    label_y = piece[:y]

    font_size = piece[:inner_r] * 0.18

    # Two lines: radius and width
    <<~SVG
      <text x="#{fmt(label_x)}" y="#{fmt(label_y - font_size * 0.3)}" style="font-family: Arial, sans-serif; font-size: #{fmt(font_size)}px; fill: #333; font-weight: bold;" text-anchor="middle">R#{piece[:radius]}"</text>
      <text x="#{fmt(label_x)}" y="#{fmt(label_y + font_size * 0.9)}" style="font-family: Arial, sans-serif; font-size: #{fmt(font_size)}px; fill: #333; font-weight: bold;" text-anchor="middle">W#{piece[:width]}"</text>
    SVG
  end

  def generate_column_labels
    ""  # Labels removed - each piece shows its own R and W values
  end

  def generate_calibration_square
    # 1" × 1" solid calibration square in bottom-right corner
    square_x = @total_width - 1.5
    square_y = @total_height - 1.5

    %(<rect x="#{fmt(square_x)}" y="#{fmt(square_y)}" width="1" height="1" class="channel" />)
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