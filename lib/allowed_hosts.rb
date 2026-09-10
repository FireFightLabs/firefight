# Empty must raise. Rails reads empty permissions as no restrictions, so ALLOWED_HOSTS=""
# would turn DNS rebinding protection off instead of locking the app down.
module AllowedHosts
  class MissingError < StandardError; end

  def self.parse!(raw, source: "ALLOWED_HOSTS")
    hosts = raw.to_s.split(",").map(&:strip).reject(&:empty?)
    raise MissingError, "#{source} must name at least one host" if hosts.empty?

    hosts
  end
end
