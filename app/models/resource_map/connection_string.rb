# Where a setting's value points, read in memory as its scheme, host, port, database and user. A connection string holds
# a password, so nothing here keeps the value, and a value that cannot be read answers nil rather than raising, since an
# error's message could carry it into a log. Reads URLs (postgres://, redis://, rediss://, mysql://, mongodb://,
# libsql:// and the rest), JDBC URLs, libpq's key=value form and the semicolon form .NET drivers use.
module ResourceMap::ConnectionString
  Parsed = Data.define(:scheme, :host, :port, :database, :user)

  # A scheme's port when the value names none, and the scheme a driver's own name stands for.
  DEFAULT_PORTS = {
    "postgresql" => 5432, "mysql" => 3306, "redis" => 6379, "rediss" => 6379, "valkey" => 6379, "valkeys" => 6379,
    "mongodb" => 27_017, "mongodb+srv" => 27_017, "sqlserver" => 1433, "oracle" => 1521, "libsql" => 443, "https" => 443,
    "http" => 80, "wss" => 443, "ws" => 80, "amqp" => 5672, "amqps" => 5671, "nats" => 4222, "memcached" => 11_211,
    "clickhouse" => 9440, "kafka" => 9092
  }.freeze
  SCHEMES = {
    "postgres" => "postgresql", "pgsql" => "postgresql", "psql" => "postgresql", "cockroachdb" => "postgresql",
    "mysql2" => "mysql", "mariadb" => "mysql", "trilogy" => "mysql", "mssql" => "sqlserver", "redis+tls" => "rediss"
  }.freeze
  # Where key=value forms name each part, whichever driver wrote them.
  HOST_KEYS = %w[host server data_source address addr hostaddr network_address].freeze
  PORT_KEYS = %w[port].freeze
  DATABASE_KEYS = %w[dbname database initial_catalog databasename].freeze
  USER_KEYS = %w[user username user_id uid].freeze
  SCHEME_BY_KEYS = { "initial_catalog" => "sqlserver", "dbname" => "postgresql" }.freeze

  # scheme says what a value with no scheme of its own is for, such as an app setting a cloud labels as PostgreSQL.
  def self.parse(value, scheme: nil)
    text = value.to_s.strip
    return if text.empty? || text.length > 4096

    found = if text.match?(%r{\A[a-z][a-z0-9+.:-]*://}i) || text.match?(/\Ajdbc:/i)
      url(text)
    elsif text.include?("=")
      pairs(text, scheme)
    end
    # A socket's path is not an address anything else reports.
    found if found&.host.present? && !found.host.start_with?("/") && found.port.to_i.positive?
  rescue StandardError
    nil
  end

  def self.url(text)
    text = text.sub(/\Ajdbc:/i, "")
    return oracle(text) if text.match?(/\Aoracle:/i)

    scheme, rest = text.split("://", 2)
    scheme = scheme_named(scheme)
    # A SQL Server JDBC URL puts its properties after semicolons rather than in a query.
    rest, properties = rest.split(";", 2) if scheme == "sqlserver"
    head, query = rest.split("?", 2)
    # The password may hold an @ or a slash, so the address starts after the last @ before the query.
    at = head.rindex("@")
    userinfo = at ? head[0...at] : nil
    authority, path = (at ? head[(at + 1)..] : head).split("/", 2)
    params = parameters(query.to_s.split("#").first, "&").merge(parameters(properties, ";"))
    host, port = address(authority.to_s.split(",").first.to_s)
    host = params.values_at(*HOST_KEYS).compact.first.to_s.split(",").first if host.blank?
    user = userinfo&.split(":", 2)&.first.presence || params.values_at(*USER_KEYS).compact.first
    database = path.to_s.split(/[\/#]/).first.presence || params.values_at(*DATABASE_KEYS).compact.first
    Parsed.new(scheme: scheme, host: decoded(host), port: (port || params["port"] || DEFAULT_PORTS[scheme]).to_i,
               database: decoded(database), user: decoded(user))
  end
  private_class_method :url

  # libpq's host=... port=... and the .NET Server=tcp:host,1433;Database=... forms.
  def self.pairs(text, scheme)
    values = text.include?(";") ? parameters(text, ";") : libpq(text)
    return if values.empty?

    scheme = scheme_named(scheme) if scheme
    scheme ||= SCHEME_BY_KEYS.find { |key, _| values.key?(key) }&.last
    raw = values.values_at(*HOST_KEYS).compact.first.to_s.sub(/\Atcp:/i, "")
    host, port = raw.include?(",") && !raw.include?(":") ? raw.split(",", 2) : address(raw.split(",").first.to_s)
    scheme ||= values.key?("server") || values.key?("data_source") ? "sqlserver" : "postgresql"
    port = (port.presence || values.values_at(*PORT_KEYS).compact.first.to_s.split(",").first.presence || DEFAULT_PORTS[scheme]).to_i
    Parsed.new(scheme: scheme, host: host, port: port, database: values.values_at(*DATABASE_KEYS).compact.first,
               user: values.values_at(*USER_KEYS).compact.first)
  end
  private_class_method :pairs

  # Oracle's thin form, jdbc:oracle:thin:@//host:port/service or @host:port:sid.
  def self.oracle(text)
    target = text.split("@", 2).last.to_s.delete_prefix("//")
    host, port = address(target.split(%r{[/:]}, 3).first(2).join(":"))
    Parsed.new(scheme: "oracle", host: host, port: (port || DEFAULT_PORTS["oracle"]).to_i, database: nil, user: nil)
  end
  private_class_method :oracle

  def self.scheme_named(scheme)
    name = scheme.to_s.downcase.sub(/\Ajdbc:/, "")
    name = name.split("+").first unless name == "mongodb+srv" || name == "redis+tls"
    SCHEMES.fetch(name, name)
  end
  private_class_method :scheme_named

  # A host and an optional port, a bracketed IPv6 address included.
  def self.address(authority)
    if authority.start_with?("[")
      host, port = authority.delete_prefix("[").split("]", 2)
      [ host, port.to_s.delete_prefix(":").presence ]
    elsif authority.count(":") == 1
      authority.split(":", 2).map(&:presence)
    else
      [ authority.presence, nil ]
    end
  end
  private_class_method :address

  def self.parameters(text, separator)
    text.to_s.split(separator).each_with_object({}) do |pair, found|
      key, value = pair.split("=", 2)
      next if key.blank? || value.nil?

      found[key.strip.downcase.gsub(/[\s-]+/, "_")] ||= decoded(value.strip)
    end
  end
  private_class_method :parameters

  # key=value pairs separated by spaces, a value quoted when it holds one.
  def self.libpq(text)
    text.scan(/(\w+)\s*=\s*(?:'((?:[^'\\]|\\.)*)'|(\S*))/).to_h do |key, quoted, bare|
      [ key.downcase, quoted ? quoted.gsub(/\\(.)/, '\1') : bare ]
    end
  end
  private_class_method :libpq

  # Percent escapes decoded, and a stray percent sign left as written.
  def self.decoded(text)
    text && URI.decode_uri_component(text.to_s)
  rescue ArgumentError
    text.to_s
  end
  private_class_method :decoded
end
