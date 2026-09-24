# Who owns a path, read from a CODEOWNERS file. The last matching line wins, as on the code hosts that use the format.
class CodeChange::Owners
  Rule = Data.define(:pattern, :owners)

  def initialize(text)
    @rules = text.to_s.each_line.filter_map do |line|
      pattern, *owners = line.sub(/#.*/, "").split
      Rule.new(pattern: pattern, owners: owners) if pattern && owners.any?
    end
  end

  def for(path)
    @rules.reverse.find { |rule| matches?(rule.pattern, path) }&.owners || []
  end

  private

  # A pattern with no slash but a trailing one matches at any depth. A leading slash anchors it at the root.
  def matches?(pattern, path)
    glob = pattern.delete_prefix("/")
    glob = "#{glob}**" if glob.end_with?("/")
    glob = "**/#{glob}" unless pattern.start_with?("/") || glob.delete_suffix("/**").include?("/")
    flags = File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB

    File.fnmatch?(glob, path, flags) || File.fnmatch?("#{glob}/**", path, flags)
  end
end
