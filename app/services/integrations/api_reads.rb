module Integrations
  # The general read a pack offers as api_read, for whatever its named tools do not cover. It only reads, so it never
  # asks the person and investigations and watches take it like any read. The provider's read guard refuses a call it
  # cannot show reads before anything is sent, and answer keeps secrets to their names.
  module ApiReads
    TOOL = "api_read".freeze
    GET = "GET".freeze
    # Past this an answer is cut, with a line saying so, and a long answer in a chat is saved and read by line or search.
    RESULT_LIMIT = 40_000
    QUERY_NAME = /\A[A-Za-z0-9_.\[\]$-]{1,64}\z/
    QUERY_VALUE_LIMIT = 500
    # Plain segments only, so a path never climbs out of the API with .., an encoded character, a query or a fragment.
    # Braces are taken for the ids some APIs write in them, such as Bitbucket's {uuid}, and sent encoded.
    PATH = %r{\A(/[A-Za-z0-9_.~@:=,+{}-]+)+/?\z}
    BRACES = { "{" => "%7B", "}" => "%7D" }.freeze
    CLIMB = %r{(\A|/)\.\.?(/|\z)}
    HIDDEN = "[hidden]".freeze
    ADDRESS = %r{\A(?<scheme>[a-z][a-z0-9+.-]*)://(?:[^/?#@\s]*@)?(?<host>[^/?#\s]+)}i
    # Fields that hold a secret's value wherever they sit, kept to the names inside them.
    SECRET_FIELDS = /secret|passw|token|credential|private.?key|api.?key|access.?key|signing.?key|client.?key|ssh.?key|
                     connection.?(string|info|uri|url)|database.?url|\Adsn\z|\Aenv\z|\Aenvs\z|env.?vars?|environment.?variables?|
                     build.?arg|\Avariables\z|\Avars\z/xi
    # A page's token says where the next page starts, which is no secret.
    PAGING = /\A(next|prev|previous|continuation)_?(page_?)?token\z|\Apage_?token\z|token_?type|expir/i
    # What describes a secret rather than holding it stays readable.
    DESCRIBING = %w[id key name description type kind target scope created_at createdAt updated_at updatedAt].freeze

    PATH_PARAMS = {
      "path" => { "type" => "string", "description" => "The API path to read, as the API reference writes it with its ids filled in" },
      "query" => { "type" => "object",
                   "description" => "Query parameters by name, each text, a number, true or false, such as {\"limit\": 20}. Never put " \
                                    "them in the path (optional)" }
    }.freeze

    def self.path_schema(example)
      params = PATH_PARAMS.merge("path" => PATH_PARAMS["path"].merge("description" => "#{PATH_PARAMS['path']['description']}, such as #{example}"))
      { "type" => "object", "properties" => params, "required" => %w[path] }
    end

    def self.path!(given)
      path = given.to_s.strip
      path = "/#{path}" unless path.start_with?("/")
      raise ReadGuards::Refused, "path is a plain API path, such as /services, with query parameters in query." if path.match?(CLIMB) || !path.match?(PATH)

      (path.chomp("/").presence || "/").gsub(/[{}]/, BRACES)
    end

    # A value is plain text the client encodes, so nothing in it can reach the path.
    def self.query!(query)
      return {} if query.nil?
      raise ReadGuards::Refused, "query must be an object of parameter names to values, such as {\"limit\": 20}." unless query.is_a?(Hash)

      query.to_h do |name, value|
        name = name.to_s
        raise ReadGuards::Refused, "#{name.inspect} is not a query parameter name." unless name.match?(QUERY_NAME)

        [ name, value.is_a?(Array) ? value.map { |each| query_value(name, each) } : query_value(name, value) ]
      end
    end

    def self.query_value(name, value)
      unless value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
        raise ReadGuards::Refused, "The query parameter #{name} must be text, a number, true or false."
      end

      text = value.to_s
      raise ReadGuards::Refused, "The query parameter #{name} is too long or holds a control character." if text.length > QUERY_VALUE_LIMIT || text.match?(/[[:cntrl:]]/)

      text
    end
    private_class_method :query_value

    def self.asked(path, query)
      pairs = query.flat_map { |name, value| Array(value).map { |each| [ name, each ] } }
      "#{GET} #{pairs.any? ? "#{path}?#{URI.encode_www_form(pairs)}" : path}"
    end

    # A connection made for every scope the credential reads reaches whatever a read names.
    def self.outside_scopes(settings, named, words)
      return nil if settings.scope_field.nil? || settings.all_scopes?

      outside = named.compact.map(&:to_s).uniq - settings.chosen_scopes
      return nil if outside.empty?

      "This connection reads #{settings.chosen_scopes.map { |id| settings.scope_name(id) }.to_sentence} only, and the read reaches " \
        "#{outside.to_sentence}. Read inside the #{words} it reaches, or connect the other one."
    end

    # One field to a line, so a long answer saved in a chat can be searched. secret is true where the whole answer holds
    # secret values, such as a list of environment variables.
    # webhooks is true for a list or read of webhooks, whose events, state and last delivery are worth reading while their
    # address can carry the receiver's token, so every address keeps only its host.
    def self.answer(provider, asked, said, secret: false, webhooks: false)
      shown = shown(said, secret: secret, webhooks: webhooks)
      text = Chat::SecretFree.redacted(shown.is_a?(String) ? shown : JSON.pretty_generate(shown))
      cut = text.length > RESULT_LIMIT
      text = "#{text[0, RESULT_LIMIT]}\n[Cut at #{RESULT_LIMIT} characters. Read less at once, such as one page with a smaller limit, or one item by its id.]" if cut
      "#{provider} answered #{asked}.\n#{text}"
    end

    # The answer as the API gave it with secrets kept to their names, whole, as answer writes it for the model and as a
    # provider's own command line tool reads it back through Halon's terminal (Telemetry::RELAYED).
    def self.shown(said, secret: false, webhooks: false)
      shown = secret ? names_only(said) : without_secrets(said)
      webhooks ? hosts_only(shown) : shown
    end

    def self.hosts_only(value)
      case value
      when Hash then value.transform_values { |inner| hosts_only(inner) }
      when Array then value.map { |inner| hosts_only(inner) }
      when ADDRESS then "#{Regexp.last_match(:scheme)}://#{Regexp.last_match(:host)}/#{HIDDEN}"
      else value
      end
    end

    def self.without_secrets(value)
      case value
      when Hash then value.to_h { |key, inner| [ key, secret_field?(key) ? names_only(inner) : without_secrets(inner) ] }
      when Array then value.map { |inner| without_secrets(inner) }
      else value
      end
    end

    def self.secret_field?(key)
      name = key.to_s
      name.match?(SECRET_FIELDS) && !name.match?(PAGING) && !DESCRIBING.include?(name)
    end

    def self.names_only(value)
      case value
      when Hash
        value.to_h do |key, inner|
          kept = DESCRIBING.include?(key.to_s) && !inner.is_a?(Hash) && !inner.is_a?(Array)
          [ key, kept ? inner : (inner.is_a?(Hash) || inner.is_a?(Array) ? names_only(inner) : HIDDEN) ]
        end
      when Array then value.map { |inner| names_only(inner) }
      when nil then nil
      else HIDDEN
      end
    end
  end
end
