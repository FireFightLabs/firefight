# Parses ALLOWED_HOSTS into the list Rails' host authorization enforces.
#
# The empty case has to raise rather than return an empty array. Rails reads
# empty permissions as "no restrictions" and skips the check entirely, so
# ALLOWED_HOSTS="" would quietly turn DNS rebinding protection off instead of
# locking the app down. Refusing to boot is the safer failure, and it is loud.
module AllowedHosts
  class MissingError < StandardError; end

  def self.parse!(raw, source: "ALLOWED_HOSTS")
    hosts = raw.to_s.split(",").map(&:strip).reject(&:empty?)
    raise MissingError, "#{source} must name at least one host" if hosts.empty?

    hosts
  end
end
