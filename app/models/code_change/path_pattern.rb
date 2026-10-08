# A path a person writes to keep code changes off some files, read the way a .gitignore line is. A folder ends in / and
# holds everything under it. A pattern with no / inside it, such as *.lock, matches a name at any depth, and one with a /
# matches from the repository's root. * is any run of characters within a name, ** any number of folders and ? one
# character. Nothing here knows a code host.
module CodeChange::PathPattern
  MAX_LENGTH = 200
  # A pattern Firefight would read differently from how a person meant it is refused rather than matched by surprise.
  UNREAD = /[\[\]{}\\]/
  EXAMPLE = "infra/prod/".freeze

  # Why the pattern cannot be kept, as a sentence, or nil when it can.
  def self.refusal(pattern)
    if pattern.length > MAX_LENGTH
      "#{pattern.truncate(40)} is longer than #{MAX_LENGTH} characters."
    elsif pattern.start_with?("!")
      "#{pattern} is an exception, and the list has none. List only the paths Halon may not change."
    elsif pattern.match?(UNREAD)
      "#{pattern} uses [ ], { } or \\, which this list does not read. Use *, ** and ?, or list each path on its own line."
    elsif pattern.split("/").include?("..")
      "#{pattern} reaches outside the repository. Give a path inside it, such as #{EXAMPLE}"
    elsif body(pattern).empty?
      "#{pattern} names no file or folder. Give one, such as #{EXAMPLE}"
    end
  end

  # Whether the pattern covers a path in a repository, given from its root without a leading /.
  def self.match?(pattern, path) = path.to_s.match?(regexp(pattern))

  # What the pattern says once the ./ or / it may start with and the / a folder ends with are set aside.
  def self.body(pattern) = pattern.to_s.strip.delete_prefix("./").delete_prefix("/").sub(%r{/+\z}, "")

  def self.regexp(pattern)
    text = pattern.to_s.strip.delete_prefix("./")
    rooted = text.start_with?("/") || body(text).include?("/")
    start = rooted ? '\A' : '(?:\A|/)'
    finish = text.end_with?("/") ? "/" : '(?:/|\z)'
    Regexp.new("#{start}#{translated(body(text))}#{finish}")
  end

  def self.translated(text)
    text.scan(%r{\*\*/|\*\*|\*|\?|[^*?]+}).map do |token|
      case token
      when "**/" then "(?:.*/)?"
      when "**" then ".*"
      when "*" then "[^/]*"
      when "?" then "[^/]"
      else Regexp.escape(token)
      end
    end.join
  end

  private_class_method :regexp, :translated
end
