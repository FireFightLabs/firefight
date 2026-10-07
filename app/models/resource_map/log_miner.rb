# Turns log lines into the patterns they follow, such as "GET /orders/<NUM> <NUM> in <NUM> ms", so a week of a service's
# logs reads as a few hundred kinds of line rather than thousands of lines. Every line is scrubbed of anything that
# looks like a credential first, then its values are masked, then a Drain style token tree groups the lines. Lines of
# the same length that start alike are compared token by token, and a line close enough to a group joins it, the tokens
# that differ becoming <*>. Nothing of a line is kept but its pattern.
class ResourceMap::LogMiner
  WILDCARD = "<*>".freeze
  LEVEL_ERROR = "error".freeze
  LEVEL_WARNING = "warning".freeze
  LEVELS = [ LEVEL_ERROR, LEVEL_WARNING ].freeze
  # How alike a line must be to a group's pattern to join it, as the share of its tokens that match.
  SIMILARITY = 0.5
  # The tokens after the length that pick a branch of the tree. One, so lines that differ in their second word, such as
  # the name in "user ada logged in", still meet.
  PREFIX_TOKENS = 1
  MAX_CHILDREN = 100
  MAX_LINE = 2_000
  MAX_TEMPLATE = 500
  MAX_TOKENS = 80

  # Applied in order, so a timestamp is masked before its numbers and a URL's query before its path.
  MASKS = [
    [ /\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?/, "<TIME>" ],
    [ %r{\b\d{1,2}/(?:[A-Z][a-z]{2}|\d{1,2})/\d{2,4}(?::\d{2}:\d{2}:\d{2})?(?: [+-]\d{4})?}, "<TIME>" ],
    [ /\b(?:[A-Z][a-z]{2} ){1,2}\s?\d{1,2} \d{2}:\d{2}:\d{2}\b/, "<TIME>" ],
    [ /\b\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\b/, "<TIME>" ],
    [ /"(?:[^"\\]|\\.)*"/, "<QUOTED>" ],
    [ /'(?:[^'\\]|\\.)*'/, "<QUOTED>" ],
    [ /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/, "<EMAIL>" ],
    [ /\?[^\s"']*/, "?<QUERY>" ],
    [ /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, "<UUID>" ],
    [ /\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b/, "<IP>" ],
    [ /(?<![\w:])(?:[0-9a-f]{0,4}:){2,7}[0-9a-f]{1,4}\b/i, "<IP>" ],
    [ /\b0x[0-9a-f]+\b/i, "<HEX>" ],
    [ /\b(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{8,}\b/i, "<HEX>" ],
    [ /\b[0-9a-f]{16,}\b/i, "<HEX>" ],
    [ /(?<![A-Za-z<])[-+]?\d+(?:\.\d+)?/, "<NUM>" ]
  ].freeze
  ERROR = /\b(?:ERROR|ERR|FATAL|CRITICAL|CRIT|PANIC|EMERG|ALERT|Exception|Traceback|Error:)\b|level[=:"\s]+"?(?:error|fatal|critical)\b/i
  WARNING = /\b(?:WARN|WARNING)\b|level[=:"\s]+"?warn(?:ing)?\b/i

  # One pattern and how many of the lines read follow it. level is error, warning or nil.
  Pattern = Data.define(:template, :lines, :level) do
    def tokens = template.split(" ")
  end

  # Where an answer in JSON keeps a line's words, under the names log stores give them.
  MESSAGE_KEYS = %w[message msg body line log text content @message _msg].freeze
  # The line Integrations::Telemetry starts a logs answer with, which is no line of the logs.
  HEADER = /\A(?:\d+ log lines for |No log lines matched )/
  # The time Integrations::Telemetry starts each line with, which says when, not what kind of line it is.
  STAMPED = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s+/

  # The log lines in a logs capability's answer: its text less the header and the link back to the provider, or for an
  # answer in JSON, the messages it holds. Nothing here knows which provider answered.
  def self.lines_of(result)
    Array(result.is_a?(Hash) ? result["content"] || result[:content] : nil).flat_map do |part|
      text = (part["text"] || part[:text]).to_s
      parsed = parse(text)
      next messages(parsed) if parsed

      kept = text.lines(chomp: true).reject { |line| line.strip.empty? || HEADER.match?(line) || Integrations::Telemetry.link_line?(line) }
      kept.map { |line| line.sub(STAMPED, "") }
    end
  end

  def self.parse(text)
    return unless text.lstrip.start_with?("{", "[")

    parsed = JSON.parse(text)
    parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def self.messages(value)
    case value
    when Array then value.flat_map { |each| messages(each) }
    when Hash
      found = value.slice(*MESSAGE_KEYS).values.grep(String)
      found.any? ? [ found.first ] : value.values.flat_map { |each| messages(each) }
    else []
    end
  end
  private_class_method :parse, :messages

  # A line as the miner reads it: scrubbed, masked, cut to a length and split into tokens.
  def self.masked(line)
    scrubbed = Chat::SecretFree.redacted(line.to_s.truncate(MAX_LINE, omission: ""))
    MASKS.reduce(scrubbed) { |text, (pattern, mask)| text.gsub(pattern, mask) }.squish
  end

  def self.level_of(line)
    return LEVEL_ERROR if line.match?(ERROR)

    LEVEL_WARNING if line.match?(WARNING)
  end

  # The patterns lines follow, most lines first. The same lines in any order give the same patterns, since lines are
  # grouped as identical masked text first and fed to the tree by how often each was seen.
  def self.mine(lines, keep: nil)
    counted = Hash.new(0)
    levels = {}
    lines.each do |line|
      text = masked(line)
      next if text.empty?

      counted[text] += 1
      levels[text] ||= level_of(line)
    end
    miner = new
    counted.sort_by { |text, count| [ -count, text ] }.each { |text, count| miner.add(text, count, levels[text]) }
    patterns = miner.patterns
    keep ? patterns.first(keep) : patterns
  end

  # Each line's pattern among known ones, or nil for a line that follows none, matched the way the tree groups them.
  def self.known_by(templates)
    miner = new
    templates.each { |template| miner.seed(template) }
    miner
  end

  def initialize
    @tree = {}
    @groups = []
  end

  def add(text, count = 1, level = nil)
    tokens = text.split(" ").first(MAX_TOKENS)
    group = match(tokens)
    if group
      group[:tokens] = merged(group[:tokens], tokens)
      group[:lines] += count
      group[:level] = more_severe(group[:level], level)
    else
      group = { tokens: tokens, lines: count, level: level }
      @groups << group
      leaf(tokens) << group
    end
    group
  end

  # A known pattern, matched against but never widened.
  def seed(template)
    tokens = template.split(" ")
    group = { tokens: tokens, lines: 0, level: nil, template: template }
    leaf(tokens) << group
    group
  end

  # The known pattern a masked line follows, or nil.
  def known(text)
    tokens = text.split(" ").first(MAX_TOKENS)
    match(tokens)&.dig(:template)
  end

  def patterns
    @groups.map { |group| Pattern.new(template: group[:tokens].join(" ").truncate(MAX_TEMPLATE), lines: group[:lines], level: group[:level]) }
           .sort_by { |pattern| [ -pattern.lines, pattern.template ] }
  end

  private

  # Lines of one length, then by their first tokens, where a token holding a number or a mask counts as any.
  def leaf(tokens)
    node = (@tree[tokens.size] ||= {})
    tokens.first(PREFIX_TOKENS).each do |token|
      key = token.match?(/\d|<[A-Z*]+>/) ? WILDCARD : token
      key = WILDCARD if !node.key?(key) && node.size >= MAX_CHILDREN
      node = (node[key] ||= {})
    end
    node[:groups] ||= []
  end

  def match(tokens)
    candidates = leaf(tokens)
    best = candidates.max_by { |group| [ similarity(group[:tokens], tokens), group[:tokens].count(WILDCARD) * -1 ] }
    best if best && similarity(best[:tokens], tokens) >= SIMILARITY
  end

  def similarity(template, tokens)
    return 0.0 unless template.size == tokens.size && tokens.any?

    template.zip(tokens).count { |known, token| known == WILDCARD || known == token }.fdiv(tokens.size)
  end

  def merged(template, tokens) = template.zip(tokens).map { |known, token| known == token ? known : WILDCARD }

  def more_severe(first, second) = [ first, second ].include?(LEVEL_ERROR) ? LEVEL_ERROR : (first || second)
end
