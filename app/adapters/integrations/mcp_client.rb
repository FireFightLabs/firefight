module Integrations
  # Initialize returns an Mcp-Session-Id every later request must echo, and
  # the spec requires notifications/initialized before other calls.
  class McpClient
    class Error < Integrations::Error; end

    PROTOCOL_VERSION = "2025-06-18".freeze
    READ_TIMEOUT = 30
    # A server may list its tools a page at a time. This bounds how many pages are read, so a server that repeats its
    # cursor cannot hold a refresh forever.
    MAX_TOOL_PAGES = 50

    # within bounds a whole tool call, its handshake included, in seconds. Without it each request waits READ_TIMEOUT.
    # checked_for names the provider whose INTEGRATION_<KEY>_PRIVATE_HOSTS may allow a private address, for a server
    # address a workspace pasted. Such an address is checked before anything is sent (PublicAddress), and every request
    # goes to the address checked. nil is a server the registry names, which needs no check.
    def initialize(server_url:, headers: {}, within: nil, checked_for: nil)
      @server_url = server_url
      @headers = headers
      @within = within
      @checked_for = checked_for
      @session_id = nil
      @initialized = false
      @id = 0
    end

    def ping
      ensure_initialized
      true
    end

    def tools_list
      ensure_initialized
      tools = []
      cursor = nil
      MAX_TOOL_PAGES.times do
        page = request("tools/list", cursor ? { cursor: cursor } : {})
        tools.concat(Array(page["tools"]))
        cursor = page["nextCursor"].presence
        return tools unless cursor
      end
      raise Error, "the server listed more than #{MAX_TOOL_PAGES} pages of tools"
    end

    def call_tool(name:, arguments:)
      @deadline = now + @within if @within
      ensure_initialized
      request("tools/call", { name: name, arguments: arguments })
    end

    private

    def ensure_initialized
      return if @initialized

      result = request("initialize", {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: { name: "firefight", version: "1.0" }
      })
      notify("notifications/initialized")
      @initialized = true
      result
    end

    def request(method, params = {})
      response = post({ jsonrpc: "2.0", id: (@id += 1), method: method, params: params })
      capture_session(response)
      raise Error, "MCP server returned HTTP #{response.code}" unless success?(response)

      body = parse_body(response)
      raise Error, "MCP error: #{body.dig('error', 'message') || 'unknown error'}" if body["error"]

      body.fetch("result", {})
    end

    # Notifications have no id and get a bodiless 202.
    def notify(method)
      response = post({ jsonrpc: "2.0", method: method })
      capture_session(response)
    end

    def post(payload)
      uri = URI.parse(@server_url.to_s)
      raise Error, "invalid MCP server URL" unless uri.is_a?(URI::HTTP)

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json, text/event-stream"
      req["MCP-Protocol-Version"] = PROTOCOL_VERSION
      req["Mcp-Session-Id"] = @session_id if @session_id
      @headers.each { |key, value| req[key] = value }
      req.body = payload.to_json

      Http.request(uri, req, error_class: Error, read_timeout: read_timeout, ipaddr: address(uri))
    end

    # Checked once per client, so the name cannot point somewhere else between one request and the next.
    def address(uri)
      return unless @checked_for

      @address ||= PublicAddress.check!(uri.host, provider_key: @checked_for).ip.to_s
    rescue PublicAddress::Refused => error
      raise Error, error.message
    end

    def read_timeout
      return READ_TIMEOUT unless @deadline

      left = @deadline - now
      raise Error.new("#{URI.parse(@server_url.to_s).host} did not answer within #{@within} seconds").extend(TimedOut) unless left.positive?

      [ left, READ_TIMEOUT ].min
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def capture_session(response)
      session = response["Mcp-Session-Id"]
      @session_id = session if session.present?
    end

    def success?(response)
      response.code.to_i.between?(200, 299)
    end

    def parse_body(response)
      body = response.body.to_s
      return {} if body.empty?

      if response["Content-Type"].to_s.include?("text/event-stream")
        data = body.lines.find { |line| line.start_with?("data:") }
        raise Error, "empty SSE response" unless data

        JSON.parse(data.delete_prefix("data:").strip)
      else
        JSON.parse(body)
      end
    rescue JSON::ParserError
      raise Error, "server returned invalid JSON"
    end
  end
end
