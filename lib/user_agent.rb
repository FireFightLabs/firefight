# How Firefight names itself to the servers it calls. Some, such as those behind Cloudflare's bot protection, refuse a
# request that names no program or only Ruby's default, so every outbound request carries this unless its caller set
# one of its own.
module UserAgent
  VALUE = "Firefight/1.0 (+https://firefight.app)".freeze
  RUBY_DEFAULT = "Ruby".freeze

  def self.apply!(request)
    current = request["User-Agent"].to_s
    request["User-Agent"] = VALUE if current.empty? || current == RUBY_DEFAULT
    request
  end
end
