require "vips"

# Draws a chart as a PNG, for places that cannot draw one themselves, such as a Slack thread. It draws with libvips'
# own line, box and text functions. It never loads an SVG, since image_processing blocks libvips' untrusted loaders,
# SVG among them, for every upload in the app.
class Chat::Chart::Image
  WIDTH = 960
  LEFT = 72
  RIGHT = 24
  TOP = 72
  PLOT_HEIGHT = 280
  # Room under the plot for the time labels, then one legend row per two series, each wide enough for a container name.
  AXIS_ROOM = 40
  LEGEND_ROW = 22
  LEGEND_COLUMNS = 2
  LEGEND_LABEL = 52
  MARGIN = 20
  DAY = 24 * 60 * 60
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

  def height = legend_top + (legend_rows * LEGEND_ROW) + MARGIN

  def png
    image = (Vips::Image.black(WIDTH, height) + WHITE).cast(:uchar).copy(interpretation: :srgb)
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
    texts = [
      [ @chart.title.to_s, LEFT, 14, INK, 16, :left ], [ @chart.unit.to_s, WIDTH - RIGHT, 16, MUTED, 12, :right ],
      [ range_text(from, to), LEFT, 40, MUTED, 10, :left ]
    ]
    (0..TICKS).each do |index|
      value = low + ((high - low) * index / TICKS)
      texts << [ number(value), LEFT - 8, y(value) - 7, MUTED, 10, :right ]
      time = from + ((to - from) * index / TICKS)
      texts << [ Time.at(time).utc.strftime(tick_format(from, to)), x(time), plot_bottom + 10, MUTED, 10, :center ]
    end
    legend.each { |line, left, top| texts << [ line[:label].truncate(LEGEND_LABEL), left + 16, top - 2, INK, 10, :left ] }
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
    legend.each_with_index { |(_line, left, top), index| canvas.draw_rect!(COLORS[index], left, top, 10, 10, fill: true) }
  end

  # One series needs no key, since the title names it. Series fill two columns, row by row.
  def legend
    return [] if @series.size < 2

    column_width = (WIDTH - LEFT - RIGHT) / LEGEND_COLUMNS
    @series.each_with_index.map do |line, index|
      [ line, LEFT + ((index % LEGEND_COLUMNS) * column_width), legend_top + ((index / LEGEND_COLUMNS) * LEGEND_ROW) ]
    end
  end

  def legend_rows = @series.size < 2 ? 0 : (@series.size.to_f / LEGEND_COLUMNS).ceil

  def plot_bottom = TOP + PLOT_HEIGHT

  def legend_top = plot_bottom + AXIS_ROOM

  # Over more than a day the axis shows dates, since times alone repeat.
  def tick_format(from, to) = to - from > DAY ? "%b %-d" : "%H:%M"

  def range_text(from, to)
    start, finish = Time.at(from).utc, Time.at(to).utc
    ending = start.to_date == finish.to_date ? finish.strftime("%H:%M") : finish.strftime("%b %-d %H:%M")
    "#{start.strftime('%b %-d %H:%M')} to #{ending} UTC"
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
    image.composite2(ink, :over, x: placed_left.round.clamp(0, WIDTH - 1), y: top.round.clamp(0, height - 1)).flatten(background: WHITE).cast(:uchar).copy(interpretation: :srgb)
  end

  def all_points = @series.flat_map { |line| line[:points] }

  def time_range
    from = @chart.range_start.to_f
    to = @chart.range_end.to_f
    to > from ? [ from, to ] : [ from, from + 1 ]
  end

  # The axis starts at zero unless values go below it, so a small change does not look like a large drop. It ends on a round
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
    TOP + PLOT_HEIGHT - ((value - low) / (high - low) * PLOT_HEIGHT)
  end

  def number(value)
    rounded = value.abs >= 100 ? value.round : value.round(2)
    rounded.to_s.sub(/\.0\z/, "")
  end
end
