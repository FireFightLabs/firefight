require "vips"

# Draws a chart as a PNG, for places that cannot draw one themselves, such as a Slack thread. It draws with libvips'
# own line, box and text functions. It never loads an SVG, since image_processing blocks libvips' untrusted loaders,
# SVG among them, for every upload in the app.
class Chat::Chart::Image
  WIDTH = 960
  HEIGHT = 420
  LEFT = 72
  RIGHT = 24
  TOP = 64
  BOTTOM = 72
  COLORS = [ [ 14, 143, 163 ], [ 59, 130, 246 ], [ 16, 185, 129 ], [ 245, 158, 11 ], [ 139, 92, 246 ], [ 239, 68, 68 ], [ 236, 72, 153 ], [ 100, 116, 139 ] ].freeze
  WHITE = [ 255, 255, 255 ].freeze
  INK = [ 15, 23, 42 ].freeze
  MUTED = [ 100, 116, 139 ].freeze
  GRID = [ 226, 232, 240 ].freeze
  TICKS = 4
  FONT = "sans".freeze

  def initialize(chart)
    @chart = chart
    @series = Array(chart.series).first(COLORS.size).map do |line|
      points = Array(line["points"]).filter_map do |at, value|
        time = Time.zone.parse(at.to_s)
        [ time.to_f, value.to_f ] if time && !value.nil?
      end
      { label: line["label"].to_s, points: points.sort_by(&:first) }
    end
  end

  def png
    image = (Vips::Image.black(WIDTH, HEIGHT) + WHITE).cast(:uchar).copy(interpretation: :srgb)
    image = image.mutate do |canvas|
      draw_grid(canvas)
      draw_lines(canvas)
      draw_swatches(canvas)
    end
    labels.each { |text, left, top, color, size, align| image = write(image, text, left, top, color, size, align) }
    image.write_to_buffer(".png")
  end

  # Every piece of text on the chart, with where it goes, so a test can read what the image says.
  def labels
    low, high = value_range
    from, to = time_range
    texts = [ [ @chart.title.to_s, LEFT, 16, INK, 16, :left ], [ @chart.unit.to_s, WIDTH - RIGHT, 18, MUTED, 12, :right ] ]
    (0..TICKS).each do |index|
      value = low + ((high - low) * index / TICKS)
      texts << [ number(value), LEFT - 8, y(value) - 7, MUTED, 10, :right ]
      time = from + ((to - from) * index / TICKS)
      texts << [ Time.at(time).utc.strftime("%H:%M"), x(time), HEIGHT - BOTTOM + 10, MUTED, 10, :center ]
    end
    @series.each_with_index { |line, index| texts << [ line[:label].truncate(18), LEFT + (index * 150) + 16, HEIGHT - 30, INK, 10, :left ] }
    texts << [ "#{Time.at(from).utc.strftime('%b %-d %H:%M')} to #{Time.at(to).utc.strftime('%H:%M')} UTC", WIDTH - RIGHT, HEIGHT - 30, MUTED, 10, :right ]
    texts
  end

  private

  def draw_grid(canvas)
    low, high = value_range
    (0..TICKS).each do |index|
      row = y(low + ((high - low) * index / TICKS)).round
      canvas.draw_line!(GRID, LEFT, row, WIDTH - RIGHT, row)
    end
  end

  # Each series is drawn twice, a pixel apart, so its line is two pixels thick.
  def draw_lines(canvas)
    @series.each_with_index do |line, index|
      line[:points].each_cons(2) do |(first_time, first_value), (second_time, second_value)|
        from_x, from_y, to_x, to_y = x(first_time).round, y(first_value).round, x(second_time).round, y(second_value).round
        canvas.draw_line!(COLORS[index], from_x, from_y, to_x, to_y)
        canvas.draw_line!(COLORS[index], from_x, from_y + 1, to_x, to_y + 1)
      end
    end
  end

  def draw_swatches(canvas)
    @series.each_index do |index|
      canvas.draw_rect!(COLORS[index], LEFT + (index * 150), HEIGHT - 29, 10, 10, fill: true)
    end
  end

  def write(image, text, left, top, color, size, align)
    return image if text.blank?

    mask = Vips::Image.text(ERB::Util.html_escape(text), font: "#{FONT} #{size}", dpi: 96)
    ink = mask.new_from_image(color).cast(:uchar).bandjoin(mask).copy(interpretation: :srgb)
    placed_left = case align
    when :right then left - mask.width
    when :center then left - (mask.width / 2)
    else left
    end
    image.composite2(ink, :over, x: placed_left.round.clamp(0, WIDTH - 1), y: top.round.clamp(0, HEIGHT - 1)).flatten(background: WHITE).cast(:uchar).copy(interpretation: :srgb)
  end

  def all_points = @series.flat_map { |line| line[:points] }

  def time_range
    from = @chart.range_start.to_f
    to = @chart.range_end.to_f
    to > from ? [ from, to ] : [ from, from + 1 ]
  end

  # The axis starts at zero unless values go below it, so a small change does not look like a cliff. It ends on a round
  # step, 1, 2, 2.5 or 5 times a power of ten, so the grid lines read as round numbers.
  def value_range
    @value_range ||= begin
      values = all_points.map(&:last)
      low = [ values.min || 0, 0 ].min
      high = values.max || 1
      high = low + 1 if high <= low
      step = round_step((high - low).to_f / TICKS)
      [ ((low / step).floor * step).to_f, ((high / step).ceil * step).to_f ]
    end
  end

  def round_step(raw)
    power = 10**Math.log10(raw).floor
    [ 1, 2, 2.5, 5, 10 ].map { |multiple| multiple * power }.find { |step| step >= raw }
  end

  def x(time)
    from, to = time_range
    LEFT + ((time - from) / (to - from) * (WIDTH - LEFT - RIGHT))
  end

  def y(value)
    low, high = value_range
    plot_height = HEIGHT - TOP - BOTTOM
    TOP + plot_height - ((value - low) / (high - low) * plot_height)
  end

  def number(value)
    rounded = value.abs >= 100 ? value.round : value.round(2)
    rounded.to_s.sub(/\.0\z/, "")
  end
end
