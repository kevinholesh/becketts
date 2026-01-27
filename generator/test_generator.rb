#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Piece Generator for CNC cutting track curve samples
# Generates arc channels at various radii and track widths
# Edit the constants below to customize the test pieces

# Test parameters
# NOTE: All radius values are CENTERLINE radii (distance from arc center to track centerline).
# To convert from inner edge radius: centerline_radius = inner_edge_radius + (track_width / 2)
RADII = [2.5, 3.0, 3.5, 4.0, 4.5, 5.0]  # inches, centerline radius
TRACK_WIDTHS = [1.75, 1.85, 1.95, 2.05]  # inches, inner channel width
CUT_DEPTH = 0.375  # 3/8 inch
ARC_DEGREES = 180  # degrees of arc (full half turn)

# Layout parameters
PADDING = 0.5  # inches between pieces
MIN_GAP = 0.12  # minimum gap between nested arcs for router bit

# Background grid settings (matching track_generator.rb)
SHOW_BACKGROUND_GRID = true
GRID_SIZE_IN = 1.0                # Grid cell size in inches
GRID_COLOR = '#CCCCCC'            # Light gray for subtle grid
GRID_LINE_WIDTH_IN = 0.02         # Thin grid lines (inches)

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
    # Top-right point of each arc aligned to whole-inch grid coordinates
    @layout = []
    @column_positions = []

    max_outer = RADII.max + TRACK_WIDTHS.max / 2.0

    # Round spacing to whole inches for grid alignment
    col_spacing = (max_outer + PADDING).ceil  # Space between column centers
    row_spacing = (max_outer * 2 + PADDING).ceil  # Space between row tops (diameter + padding)
    first_col_x = max_outer.ceil  # First column x (enough room for largest arc to the left)
    first_row_top_y = 1  # First row top-right point y (1" from top edge)

    # Grid: columns (widths) × rows (radii)
    TRACK_WIDTHS.each_with_index do |width, col_idx|
      col_x = first_col_x + col_idx * col_spacing

      RADII.sort.reverse.each_with_index do |radius, row_idx|
        piece = @pieces.find { |p| p[:width] == width && p[:radius] == radius }
        # Position by top-right point: top_y is grid-aligned, center_y = top_y + outer_r
        top_y = first_row_top_y + row_idx * row_spacing
        center_y = top_y + piece[:outer_r]

        piece[:x] = col_x
        piece[:y] = center_y
        piece[:arc_bottom] = center_y + piece[:outer_r]
        @layout << piece
      end

      @column_positions << { x: col_x, y: 0.2, width: width }
    end

    # Calculate total bounds - add margin for calibration square
    last_col_x = first_col_x + (TRACK_WIDTHS.size - 1) * col_spacing
    last_row_top_y = first_row_top_y + (RADII.size - 1) * row_spacing
    # Last row bottom = last_row_top_y + 2 * max_outer (full diameter of largest arc)
    @total_width = last_col_x + 2  # Room for calibration square
    @total_height = (last_row_top_y + max_outer * 2).ceil + 2  # Room for arc + margin
  end

  def generate_svg
    svg = []
    svg << svg_header
    svg << svg_styles
    svg << generate_grid

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

  def generate_individual_svgs(output_dir)
    # Create output directory
    Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

    files_created = []

    @pieces.each do |piece|
      svg_content = generate_individual_svg(piece)
      filename = "cr#{piece[:radius]}_w#{piece[:width]}.svg"
      filepath = File.join(output_dir, filename)
      File.write(filepath, svg_content)
      files_created << filename
    end

    files_created
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

  def generate_grid
    return "" unless SHOW_BACKGROUND_GRID

    # Create background grid pattern (1" x 1" subtle grid)
    # With patternUnits="userSpaceOnUse", grid lines naturally align to whole numbers in user space
    # ViewBox starts at 0,0 so grid aligns with top-left edge
    %(<defs>
<pattern id="background-grid" width="#{GRID_SIZE_IN}" height="#{GRID_SIZE_IN}" patternUnits="userSpaceOnUse">
<path d="M #{GRID_SIZE_IN} 0 L 0 0 0 #{GRID_SIZE_IN}" fill="none" stroke="#{GRID_COLOR}" stroke-width="#{GRID_LINE_WIDTH_IN}"/>
</pattern>
</defs>
<rect x="0" y="0" width="#{@total_width}" height="#{@total_height}" fill="url(#background-grid)"/>)
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
      <text x="#{fmt(label_x)}" y="#{fmt(label_y - font_size * 0.3)}" style="font-family: Arial, sans-serif; font-size: #{fmt(font_size)}px; fill: #333; font-weight: bold;" text-anchor="middle">CR#{piece[:radius]}"</text>
      <text x="#{fmt(label_x)}" y="#{fmt(label_y + font_size * 0.9)}" style="font-family: Arial, sans-serif; font-size: #{fmt(font_size)}px; fill: #333; font-weight: bold;" text-anchor="middle">W#{piece[:width]}"</text>
    SVG
  end

  def generate_column_labels
    ""  # Labels removed - each piece shows its own R and W values
  end

  def generate_calibration_square
    # 1" × 1" solid calibration square aligned to grid in bottom-right corner
    square_x = @total_width - 2  # Aligned to whole inch
    square_y = @total_height - 2  # Aligned to whole inch

    %(<rect x="#{square_x}" y="#{square_y}" width="1" height="1" class="channel" />)
  end

  def generate_individual_svg(piece)
    # Calculate dimensions for individual piece
    # Position arc so top-right aligns with grid at (outer_r, 1)
    outer_r = piece[:outer_r]
    inner_r = piece[:inner_r]

    # Arc center position (top-right of arc at grid intersection)
    cx = outer_r.ceil  # Enough room for arc to extend left
    cy = 1 + outer_r   # Top at y=1, center below

    # SVG dimensions (whole inches for grid alignment)
    svg_width = cx + 2  # Room for calibration square on right
    svg_height = (cy + outer_r).ceil + 2  # Room for arc bottom + margin

    svg = []
    svg << %(<?xml version="1.0" encoding="UTF-8"?>)
    svg << %(<svg xmlns="http://www.w3.org/2000/svg")
    svg << %(     width="#{svg_width}in")
    svg << %(     height="#{svg_height}in")
    svg << %(     viewBox="0 0 #{svg_width} #{svg_height}">)

    # Styles
    svg << %(<style>)
    svg << %(  .channel { fill: #333333; stroke: none; })
    svg << %(  .label { font-family: Arial, sans-serif; font-size: 0.18px; fill: #333; })
    svg << %(</style>)

    # White background
    svg << %(<rect width="100%" height="100%" fill="white" />)

    # Grid
    if SHOW_BACKGROUND_GRID
      svg << %(<defs>)
      svg << %(<pattern id="background-grid" width="#{GRID_SIZE_IN}" height="#{GRID_SIZE_IN}" patternUnits="userSpaceOnUse">)
      svg << %(<path d="M #{GRID_SIZE_IN} 0 L 0 0 0 #{GRID_SIZE_IN}" fill="none" stroke="#{GRID_COLOR}" stroke-width="#{GRID_LINE_WIDTH_IN}"/>)
      svg << %(</pattern>)
      svg << %(</defs>)
      svg << %(<rect x="0" y="0" width="#{svg_width}" height="#{svg_height}" fill="url(#background-grid)"/>)
    end

    # Arc channel
    start_angle = 90 * Math::PI / 180
    end_angle = (90 + ARC_DEGREES) * Math::PI / 180

    outer_start_x = cx + outer_r * Math.cos(start_angle)
    outer_start_y = cy + outer_r * Math.sin(start_angle)
    outer_end_x = cx + outer_r * Math.cos(end_angle)
    outer_end_y = cy + outer_r * Math.sin(end_angle)

    inner_start_x = cx + inner_r * Math.cos(start_angle)
    inner_start_y = cy + inner_r * Math.sin(start_angle)
    inner_end_x = cx + inner_r * Math.cos(end_angle)
    inner_end_y = cy + inner_r * Math.sin(end_angle)

    large_arc = ARC_DEGREES >= 180 ? 1 : 0

    path = "M #{fmt(outer_start_x)} #{fmt(outer_start_y)} "
    path += "A #{fmt(outer_r)} #{fmt(outer_r)} 0 #{large_arc} 1 #{fmt(outer_end_x)} #{fmt(outer_end_y)} "
    path += "L #{fmt(inner_end_x)} #{fmt(inner_end_y)} "
    path += "A #{fmt(inner_r)} #{fmt(inner_r)} 0 #{large_arc} 0 #{fmt(inner_start_x)} #{fmt(inner_start_y)} "
    path += "Z"

    svg << %(<path d="#{path}" class="channel" />)

    # Labels inside the arc
    label_x = cx - inner_r * 0.5
    label_y = cy
    font_size = inner_r * 0.18

    svg << %(<text x="#{fmt(label_x)}" y="#{fmt(label_y - font_size * 0.3)}" style="font-family: Arial, sans-serif; font-size: #{fmt(font_size)}px; fill: #333; font-weight: bold;" text-anchor="middle">CR#{piece[:radius]}"</text>)
    svg << %(<text x="#{fmt(label_x)}" y="#{fmt(label_y + font_size * 0.9)}" style="font-family: Arial, sans-serif; font-size: #{fmt(font_size)}px; fill: #333; font-weight: bold;" text-anchor="middle">W#{piece[:width]}"</text>)

    # Calibration square (1" × 1") aligned to grid
    cal_x = svg_width - 2
    cal_y = svg_height - 2
    svg << %(<rect x="#{cal_x}" y="#{cal_y}" width="1" height="1" class="channel" />)

    svg << %(</svg>)
    svg.join("\n")
  end

  def fmt(num)
    format('%.4f', num)
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  generator = TestPieceGenerator.new
  svg_content = generator.generate_svg

  # Generate combined SVG
  output_path = File.join(__dir__, 'test_pieces.svg')
  File.write(output_path, svg_content)

  # Generate individual SVGs
  individual_dir = File.join(__dir__, 'test_pieces')
  individual_files = generator.generate_individual_svgs(individual_dir)

  puts "Generated: #{output_path}"
  puts "Sheet size: %.1f\" × %.1f\"" % [generator.total_width, generator.total_height]
  puts "Pieces: #{RADII.length * TRACK_WIDTHS.length} test arcs (#{ARC_DEGREES}° each)"
  puts "Radii: #{RADII.join(', ')} inches"
  puts "Widths: #{TRACK_WIDTHS.join(', ')} inches"
  puts "Cut depth: #{CUT_DEPTH} inches"
  puts ""
  puts "Individual SVGs: #{individual_dir}/"
  puts "  #{individual_files.length} files created"

  puts ""
  print 'Opening in Cursor...'
  system("cursor", output_path)
end