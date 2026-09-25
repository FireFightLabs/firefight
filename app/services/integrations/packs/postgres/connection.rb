require "ipaddr"
require "socket"
require "tempfile"

module Integrations
  module Packs
    class Postgres < NativePack
      # One short connection per call, read only whatever the user may do, bounded in time. A host that resolves inside
      # a private network is refused unless an operator allowed it, since the connection is made from Firefight's
      # network, not the customer's.
      class Connection
        # Comma separated host names, addresses or ranges, for Firefight's own database and for self-hosting.
        ALLOWED_PRIVATE_HOSTS_ENV = "INTEGRATION_POSTGRESQL_PRIVATE_HOSTS".freeze
        CONNECT_TIMEOUT_SECONDS = 5
        STATEMENT_TIMEOUT_MS = 10_000
        LOCK_TIMEOUT_MS = 2_000
        IDLE_TIMEOUT_MS = 15_000
        APPLICATION_NAME = "Firefight Halon".freeze
        DEFAULT_PORT = 5432
        URL_FORMAT = %r{\Apostgres(ql)?://}i
        # Reserved ranges IPAddr does not call private, such as the shared range clouds use inside their own networks.
        RESERVED_RANGES = %w[0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ff00::/8].map { |range| IPAddr.new(range) }.freeze

        # Certificates are pasted as text. The driver reads them from files, so each call writes its own and removes them.
        ROOT_CERT = "root_cert".freeze
        CLIENT_CERT = "client_cert".freeze
        CLIENT_KEY = "client_key".freeze
        CERTIFICATES = [ ROOT_CERT, CLIENT_CERT, CLIENT_KEY ].freeze
        CERTIFICATE_PEM = /-----BEGIN CERTIFICATE-----.+-----END CERTIFICATE-----/m
        KEY_PEM = /-----BEGIN [A-Z ]*PRIVATE KEY-----.+-----END [A-Z ]*PRIVATE KEY-----/m
        CERTIFICATE_FILES = { ROOT_CERT => "sslrootcert", CLIENT_CERT => "sslcert", CLIENT_KEY => "sslkey" }.freeze
        # Anything that names a file on Firefight's own servers. Certificates arrive as text instead.
        FILE_OPTIONS = %w[sslrootcert sslcert sslkey sslcrl sslcrldir passfile service servicefile].freeze
        # Over the internet a connection is encrypted. These would let it fall back to plain text.
        UNENCRYPTED_MODES = %w[disable allow].freeze
        LENIENT_MODES = [ nil, "prefer" ].freeze

        def self.open(url, certificates = {})
          new(url, certificates).open { |connection| yield connection }
        end

        # The reason a URL or its certificates cannot be used, or nil. Read before anything is saved, so it is said on the form.
        def self.refusal(url, certificates = {})
          new(url, certificates).parameters
          nil
        rescue NativePack::Error => refused
          refused.message
        end

        def initialize(url, certificates = {})
          @url = url.to_s.strip
          @certificates = certificates.to_h.transform_keys(&:to_s).slice(*CERTIFICATES).transform_values { |pem| pem.to_s.strip }.compact_blank
        end

        def open
          files = certificate_files
          connection = PG.connect(parameters.merge(files.transform_values(&:path)))
          connection.exec("BEGIN READ ONLY")
          yield connection
        rescue PG::ConnectionBad => error
          raise NativePack::Error, "Could not connect to the database: #{first_line(error)}"
        rescue PG::QueryCanceled
          raise NativePack::Error, "The query ran longer than #{STATEMENT_TIMEOUT_MS / 1000} seconds and was stopped."
        rescue PG::ReadOnlySqlTransaction
          raise NativePack::Error, "Only reading is allowed, and that statement would write."
        rescue PG::Error => error
          raise NativePack::Error, first_line(error)
        ensure
          connection&.close
          files&.each_value(&:close!)
        end

        # What the driver is given, checked whole. Certificate files are added when the connection opens.
        def parameters
          ip = address
          options = conninfo.merge(
            "hostaddr" => ip,
            "port" => (conninfo["port"].presence || DEFAULT_PORT).to_s,
            "connect_timeout" => CONNECT_TIMEOUT_SECONDS.to_s,
            "application_name" => APPLICATION_NAME,
            "options" => "-c default_transaction_read_only=on -c statement_timeout=#{STATEMENT_TIMEOUT_MS} " \
                         "-c lock_timeout=#{LOCK_TIMEOUT_MS} -c idle_in_transaction_session_timeout=#{IDLE_TIMEOUT_MS}"
          )
          check_certificates!
          @allowed_private ? options : options.merge("sslmode" => encrypted_mode)
        end

        # The address to connect to, resolved once so the name cannot point somewhere else by the time it connects.
        def address
          raise NativePack::Error, "The connection URL must start with postgres:// or postgresql://." unless @url.match?(URL_FORMAT)

          host = conninfo["host"].to_s
          raise NativePack::Error, "The connection URL has no host." if host.blank? || host.start_with?("/")
          # libpq tries each listed host in turn, and only the one checked here may be reached.
          raise NativePack::Error, "The connection URL can name one host only." if host.include?(",")

          named = (FILE_OPTIONS & conninfo.keys).reject { |option| option == "sslrootcert" && conninfo[option] == "system" }
          raise NativePack::Error, "Paste certificates in their own fields rather than naming files in the URL (#{named.join(', ')})." if named.any?

          ip = resolve(host)
          if private?(ip)
            raise NativePack::Error, "#{host} is on a private network, which Firefight does not connect to." unless allowed?(host, ip)

            @allowed_private = true
          end
          ip.to_s
        end

        private

        # A URL that does not say gets encryption required, since the driver's default quietly falls back to plain text.
        def encrypted_mode
          mode = conninfo["sslmode"]
          if UNENCRYPTED_MODES.include?(mode)
            raise NativePack::Error, "Firefight only connects over the internet with encryption. Remove sslmode=#{mode} from the URL."
          end

          LENIENT_MODES.include?(mode) ? "require" : mode
        end

        def check_certificates!
          root, cert, key = @certificates.values_at(ROOT_CERT, CLIENT_CERT, CLIENT_KEY)
          raise NativePack::Error, "The CA certificate is not a PEM certificate." if root && !root.match?(CERTIFICATE_PEM)
          raise NativePack::Error, "The client certificate is not a PEM certificate." if cert && !cert.match?(CERTIFICATE_PEM)
          raise NativePack::Error, "The client key is not a PEM private key, or it is encrypted." if key && (!key.match?(KEY_PEM) || key.include?("ENCRYPTED"))
          raise NativePack::Error, "A client certificate needs its key, and a key its certificate." if cert.nil? ^ key.nil?
        end

        # Readable by this process only, and removed when the connection closes.
        def certificate_files
          @certificates.each_with_object({}) do |(name, pem), files|
            file = Tempfile.new([ "halon-#{name}", ".pem" ])
            file.chmod(0o600)
            file.write(pem)
            file.flush
            files[CERTIFICATE_FILES.fetch(name)] = file
          end
        end

        def conninfo
          @conninfo ||= PG::Connection.conninfo_parse(@url).each_with_object({}) do |option, parsed|
            parsed[option[:keyword]] = option[:val] if option[:val].present?
          end
        rescue PG::Error
          raise NativePack::Error, "The connection URL could not be read."
        end

        def resolve(host)
          IPAddr.new(Addrinfo.getaddrinfo(host, nil, nil, :STREAM).first.ip_address)
        rescue SocketError, IPAddr::InvalidAddressError
          raise NativePack::Error, "#{host} could not be found."
        end

        def private?(ip)
          ip.private? || ip.loopback? || ip.link_local? || ip.to_s == "::" ||
            RESERVED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) } ||
            (ip.ipv4_mapped? && private?(ip.native))
        end

        def allowed?(host, ip)
          ENV.fetch(ALLOWED_PRIVATE_HOSTS_ENV, "").split(",").map(&:strip).compact_blank.any? do |entry|
            entry.casecmp?(host) || IPAddr.new(entry).include?(ip)
          rescue IPAddr::InvalidAddressError
            false
          end
        end

        # A driver error runs to several lines of detail, and the first says what went wrong.
        def first_line(error) = error.message.to_s.lines.first.to_s.sub(/\A(ERROR|FATAL):\s+/, "").strip
      end
    end
  end
end
