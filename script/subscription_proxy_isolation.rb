# Proves that the pinned subscription proxy keeps each workspace to its own subscriptions.
#
# It builds deploy/subscription-proxy, runs it on a Postgres of its own and gives it credentials for the
# five supported subscriptions the way Firefight does (upload, then prefix with the workspace's id).
# Every credential reaches its provider through a stub of its own, so which credential a request used is
# read off the stub that saw it, with the providers' real addresses and nothing sent anywhere.
#
#   ruby script/subscription_proxy_isolation.rb
#
# Needs Docker. Exits non-zero when any request for one workspace reaches a credential that is not its own.

require "fileutils"
require "json"
require "net/http"
require "open3"
require "openssl"
require "securerandom"
require "socket"
require "tmpdir"
require "uri"
require "minitest/autorun"

module SubscriptionProxyIsolation
  ROOT = File.expand_path("..", __dir__)
  PROVIDERS = (ENV["ISOLATION_PROVIDERS"] || "codex antigravity xai kimi meta").split.freeze
  MANAGEMENT_KEY = SecureRandom.hex(24)
  CLIENT_KEY = SecureRandom.hex(24)

  # Stands in for every provider. Each credential is given its own port as its outbound proxy, so a
  # connection on a port is a request made with that credential. TLS is answered with a certificate from
  # a CA only the proxy container trusts.
  class Upstream
    # Antigravity lists only the models its account says it may use.
    ANTIGRAVITY_CATALOG = {
      models: %w[
        claude-opus-4-6-thinking claude-sonnet-4-6 claude-opus-5-5-high claude-sonnet-5-5-high gemini-4-argon-high
        gemini-3.8-flash-high gemini-3-flash gemini-3.1-flash-lite gemini-3.5-flash-lite gpt-oss-120b-medium
      ].to_h { |id| [ id, {} ] }
    }.to_json

    attr_reader :ca_pem, :hits

    def initialize
      @hits = Queue.new
      @modes = {}
      @ca_key = OpenSSL::PKey::RSA.new(2048)
      @ca = certificate("Isolation test CA", @ca_key, nil, ca: true)
      @ca_pem = @ca.to_pem
      @leaf_key = OpenSSL::PKey::RSA.new(2048)
      @contexts = {}
      @lock = Mutex.new
    end

    def open_port(mode = :unavailable)
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      @modes[port] = mode
      Thread.new { loop { serve(server.accept, port) } }
      port
    end

    def set_mode(port, mode)
      @modes[port] = mode
    end

    def drain
      seen = []
      seen << @hits.pop until @hits.empty?
      seen
    end

    private

    def serve(socket, port)
      Thread.new do
        line, = read_request(socket)
        host = line.split[1].to_s.split(":").first
        warn "connect on #{port} to #{host}" if ENV["ISOLATION_DEBUG"]
        socket.write("HTTP/1.1 200 Connection established\r\n\r\n")
        tls = OpenSSL::SSL::SSLSocket.new(socket, context_for(host))
        tls.accept
        request_line, _headers, body = read_request(tls)
        catalog = request_line.include?(":fetchAvailableModels")
        sign_in = @modes.fetch(port) == :sign_in
        warn "catalog request on #{port}" if catalog && ENV["ISOLATION_DEBUG"]
        @hits << { port:, host:, request: request_line } unless catalog || sign_in
        status, payload =
          if catalog then [ 200, ANTIGRAVITY_CATALOG ]
          elsif sign_in then tokens_for(body)
          else answer(@modes.fetch(port))
          end
        tls.write("HTTP/1.1 #{status} Stub\r\nContent-Type: application/json\r\nContent-Length: #{payload.bytesize}\r\nConnection: close\r\n\r\n#{payload}")
        tls.close
      rescue StandardError => e
        warn "stub on #{port}: #{e.class} #{e.message}" if ENV["ISOLATION_DEBUG"]
        nil
      ensure
        socket.close unless socket.closed?
      end
    end

    def answer(mode)
      case mode
      when :exhausted
        [ 429, { error: { type: "usage_limit_reached", code: "usage_limit_reached", message: "The usage limit has been reached", resets_in_seconds: 3600 } }.to_json ]
      else
        [ 503, { error: { message: "unavailable" } }.to_json ]
      end
    end

    # OpenAI's token endpoint as the Codex sign-in asks it, the code naming the login (code "ana" signs in
    # ana@example.com), so two codes for one login make the same credential, as the real sign-in does.
    # A code of login~plan signs that login in on that plan, which the proxy puts in the credential's file name. A
    # refresh carries the same login in its refresh token.
    def tokens_for(body)
      form = URI.decode_www_form(body.to_s).to_h
      signed = form["code"] || form["refresh_token"].to_s.delete_prefix("refresh-")
      login, plan = signed.to_s.split("~", 2)
      claims = { email: "#{login}@example.com", "https://api.openai.com/auth" => { chatgpt_account_id: "account-#{login}", chatgpt_plan_type: plan || "plus" } }
      id_token = [ { alg: "none" }, claims ].map { |part| [ part.to_json ].pack("m0").tr("+/", "-_").delete("=") }.join(".") + ".signature"
      [ 200, { access_token: "access-#{login}", refresh_token: "refresh-#{signed}", id_token: id_token, expires_in: 3600 }.to_json ]
    end

    def read_request(io)
      line = io.gets.to_s.strip
      headers = {}
      while (header = io.gets) && header != "\r\n"
        key, value = header.split(":", 2)
        headers[key.to_s.downcase] = value.to_s.strip
      end
      body = headers["content-length"] ? io.read(headers["content-length"].to_i) : ""
      [ line, headers, body ]
    end

    def context_for(host)
      @lock.synchronize do
        @contexts[host] ||= OpenSSL::SSL::SSLContext.new.tap do |context|
          context.cert = certificate(host, @leaf_key, @ca)
          context.key = @leaf_key
          context.alpn_protocols = [ "http/1.1" ]
          context.alpn_select_cb = ->(_offered) { "http/1.1" }
        end
      end
    end

    def certificate(name, key, issuer, ca: false)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = SecureRandom.random_number(1 << 62)
      cert.subject = OpenSSL::X509::Name.parse("/CN=#{name}")
      cert.issuer = issuer ? issuer.subject : cert.subject
      cert.public_key = key.public_key
      cert.not_before = Time.now - 3600
      cert.not_after = Time.now + 86_400
      extensions = OpenSSL::X509::ExtensionFactory.new(cert, issuer || cert)
      if ca
        cert.add_extension(extensions.create_extension("basicConstraints", "CA:TRUE", true))
        cert.add_extension(extensions.create_extension("keyUsage", "keyCertSign, cRLSign", true))
      else
        cert.add_extension(extensions.create_extension("subjectAltName", "DNS:#{name}", false))
        cert.add_extension(extensions.create_extension("extendedKeyUsage", "serverAuth", false))
      end
      cert.sign(issuer ? @ca_key : key, OpenSSL::Digest.new("SHA256"))
      cert
    end
  end

  # The pinned proxy image and a Postgres of its own. The proxy shares the host's network, so it reaches
  # the stub on localhost, and listens on the port its settings name.
  class Proxy
    attr_reader :port

    # outbound is where anything a credential does not name its own proxy for goes, such as a sign-in's token exchange.
    def initialize(ca_pem, outbound:)
      @outbound = outbound
      @tag = "firefight-subscription-proxy-isolation:#{SecureRandom.hex(4)}"
      @postgres = "isolation-pg-#{SecureRandom.hex(4)}"
      @proxy = "isolation-proxy-#{SecureRandom.hex(4)}"
      @dir = Dir.mktmpdir("subscription-proxy-isolation")
      File.write(File.join(@dir, "ca.pem"), ca_pem)
      @port = 8317
      @postgres_port = free_port
    end

    def start
      docker("build", "-q", "-t", @tag, File.join(ROOT, "deploy/subscription-proxy"))
      docker("run", "-d", "--name", @postgres, "-p", "127.0.0.1:#{@postgres_port}:5432", "-e", "POSTGRES_PASSWORD=isolation", "postgres:17-alpine")
      wait_until("Postgres") { system("docker", "exec", @postgres, "pg_isready", "-h", "127.0.0.1", "-U", "postgres", out: File::NULL, err: File::NULL) }
      docker("run", "-d", "--name", @proxy, "--network", "host",
        "-v", "#{File.join(@dir, 'ca.pem')}:/isolation/ca.pem:ro",
        "-e", "SSL_CERT_FILE=/isolation/ca.pem",
        "-e", "HTTPS_PROXY=#{@outbound}", "-e", "NO_PROXY=127.0.0.1,localhost",
        "-e", "PGSTORE_DSN=postgres://postgres:isolation@127.0.0.1:#{@postgres_port}/postgres?sslmode=disable",
        "-e", "MANAGEMENT_PASSWORD=#{MANAGEMENT_KEY}",
        "-e", "PROXY_CLIENT_KEY=#{CLIENT_KEY}",
        @tag, "--local-model")
      wait_until("the proxy") { healthy? }
    end

    def stop
      [ @proxy, @postgres ].each { |name| system("docker", "rm", "-f", name, out: File::NULL, err: File::NULL) }
      system("docker", "rmi", "-f", @tag, out: File::NULL, err: File::NULL)
      FileUtils.rm_rf(@dir)
    end

    def logs
      Open3.capture2e("docker", "logs", "--tail", ENV.fetch("ISOLATION_LOG_LINES", "60"), @proxy).first
    end

    private

    def healthy?
      Net::HTTP.get_response(URI("http://127.0.0.1:#{@port}/healthz")).is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    def free_port
      server = TCPServer.new("127.0.0.1", 0)
      server.addr[1]
    ensure
      server&.close
    end

    def wait_until(what, seconds: 90)
      deadline = Time.now + seconds
      until yield
        raise "#{what} did not come up\n#{logs}" if Time.now > deadline

        Kernel.sleep 0.5
      end
    end

    def docker(*args)
      output, status = Open3.capture2e("docker", *args)
      raise "docker #{args.first} failed: #{output}" unless status.success?

      output
    end
  end

  # Talks to the proxy the way Firefight does.
  class Client
    def initialize(port)
      @base = "http://127.0.0.1:#{port}"
    end

    def upload(name, body)
      management(Net::HTTP::Post, "/v8/management/credentials?name=#{name}", body.to_json)
    end

    def patch_fields(name, fields)
      management(Net::HTTP::Patch, "/v8/management/credentials/fields", fields.merge(name:).to_json)
    end

    def reset_cooldown(name)
      files = JSON.parse(management(Net::HTTP::Get, "/v8/management/credentials?name=#{name}").body).fetch("files")
      files.each { |file| management(Net::HTTP::Post, "/v8/management/routing/cooldown/reset", { auth_index: file.fetch("auth_index") }.to_json) }
    end

    def delete(name)
      management(Net::HTTP::Delete, "/v8/management/credentials?name=#{name}")
    end

    def models_for(name)
      JSON.parse(management(Net::HTTP::Get, "/v8/management/credentials/models?name=#{name}").body).fetch("models").map { |model| model.fetch("id") }
    end

    # A Codex sign-in started the way Firefight starts one, named by its id and its workspace (or neither).
    def start_sign_in(sign_in_id: nil, workspace: nil)
      query = { provider: "codex", firefight_sign_in: sign_in_id, firefight_workspace: workspace }.compact
      JSON.parse(management(Net::HTTP::Get, "/v8/management/oauth/auth-url?#{URI.encode_www_form(query)}").body).fetch("state")
    end

    # The address the browser lands on, handed back. code names the login (see Upstream#tokens_for).
    def finish_sign_in(state, code)
      request(Net::HTTP::Post, "/v8/management/oauth/callback", MANAGEMENT_KEY, { provider: "codex", state:, code: }.to_json)
    end

    def cancel_sign_in(state)
      management(Net::HTTP::Delete, "/v8/management/oauth/session?state=#{state}")
    end

    # Waits for the proxy to settle the sign-in, and answers "ok" or why it failed.
    def settled(state)
      30.times do
        body = JSON.parse(management(Net::HTTP::Get, "/v8/management/oauth/status?state=#{state}").body)
        return body["status"] == "ok" ? "ok" : body["error"].to_s unless body["status"] == "wait"

        Kernel.sleep 0.5
      end
      "still waiting"
    end

    # What the hook says became of a sign-in: refused, credential and workspace.
    def sign_in_result(sign_in_id)
      JSON.parse(management(Net::HTTP::Get, "/firefight/sign-ins/#{sign_in_id}").body)
    end

    def refusal(sign_in_id) = sign_in_result(sign_in_id)["refused"]

    # The proxy's debug log, for finding out why a run failed (ISOLATION_PROXY_DEBUG=1).
    def debug!
      management(Net::HTTP::Patch, "/v8/management/config", { observability: { logs: { debug: true } } }.to_json)
    end

    def credentials
      JSON.parse(management(Net::HTTP::Get, "/v8/management/credentials").body).fetch("files")
    end

    def chat(model, text, cache_key: nil)
      body = { model:, messages: [ { role: "user", content: text } ] }
      body[:prompt_cache_key] = cache_key if cache_key
      inference("/v1/chat/completions", body)
    end

    def respond(model, text, cache_key: nil)
      body = { model:, input: text, stream: false }
      body[:prompt_cache_key] = cache_key if cache_key
      inference("/v1/responses", body)
    end

    private

    def inference(path, body)
      request(Net::HTTP::Post, path, CLIENT_KEY, body.to_json)
    end

    def management(verb, path, body = nil)
      response = request(verb, path, MANAGEMENT_KEY, body)
      raise "#{verb.name} #{path} failed: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      response
    end

    def request(verb, path, key, body)
      uri = URI("#{@base}#{path}")
      request = verb.new(uri)
      request["Authorization"] = "Bearer #{key}"
      request["Content-Type"] = "application/json"
      request.body = body if body
      Net::HTTP.start(uri.host, uri.port, read_timeout: 300) { |http| http.request(request) }
    end
  end

  # One provider's credential file as its sign-in leaves it, tokens that never expire included so the
  # proxy uses it without refreshing first.
  def self.credential(provider, label, port)
    far = "2099-01-01T00:00:00Z"
    base = {
      type: provider, access_token: "access-#{label}", refresh_token: "refresh-#{label}",
      email: "#{label}@example.com", expired: far, last_refresh: Time.now.utc.iso8601
    }
    extra =
      case provider
      when "codex" then { account_id: "account-#{label}", plan_type: "plus" }
      when "antigravity"
        # What the proxy keeps after asking Antigravity which models the account may use.
        catalog = { model_ids: JSON.parse(Upstream::ANTIGRAVITY_CATALOG).fetch("models").keys, project_id: "project-#{label}", endpoint: "https://daily-cloudcode-pa.googleapis.com" }
        { project_id: "project-#{label}", expires_in: 3600, timestamp: (Time.now.to_f * 1000).to_i, antigravity_capability_hints: catalog }
      when "xai" then { base_url: "https://api.x.ai/v1", auth_kind: "oauth" }
      when "kimi" then { domain: "kimi.com", base_url: "https://api.kimi.com/coding/v1" }
      when "meta" then { auth_kind: "oauth", api_key: "key-#{label}", dca_token: "dca-#{label}", dca_expired: far }
      end
    base.merge(extra, proxy_url: "http://127.0.0.1:#{port}")
  end
end

class SubscriptionProxyIsolationTest < Minitest::Test
  include SubscriptionProxyIsolation
  i_suck_and_my_tests_are_order_dependent!

  WORKSPACE_A = SecureRandom.uuid
  WORKSPACE_B = SecureRandom.uuid

  # One proxy for the whole run, since starting one takes seconds. Tests run in order and each sets the
  # state it needs.
  def self.world
    @world ||= begin
      upstream = Upstream.new
      proxy = Proxy.new(upstream.ca_pem, outbound: "http://127.0.0.1:#{upstream.open_port(:sign_in)}")
      Minitest.after_run { proxy.stop }
      proxy.start
      client = Client.new(proxy.port)
      credentials = {}
      PROVIDERS.each do |provider|
        { "a1" => WORKSPACE_A, "a2" => WORKSPACE_A, "b1" => WORKSPACE_B, "b2" => WORKSPACE_B }.each do |slot, workspace|
          name = "#{provider}-#{slot}-#{SecureRandom.hex(3)}.json"
          port = upstream.open_port
          client.upload(name, SubscriptionProxyIsolation.credential(provider, "#{provider}-#{slot}", port))
          client.patch_fields(name, prefix: workspace)
          credentials[[ provider, slot ]] = { name:, port:, workspace: }
        end
      end
      { upstream:, proxy:, client:, credentials: }
    end
  end

  # A failing upstream cools a credential down. Each test starts with every credential ready again.
  def setup
    world[:credentials].each_value { |credential| client.reset_cooldown(credential[:name]) unless credential[:deleted] }
    client.debug! if ENV["ISOLATION_PROXY_DEBUG"]
  end

  def world = self.class.world
  def client = world[:client]
  def upstream = world[:upstream]

  def ports_of(workspace, provider = nil)
    world[:credentials].select { |(name, _slot), credential| credential[:workspace] == workspace && (provider.nil? || name == provider) }.values.map { |credential| credential[:port] }
  end

  def model_for(provider, workspace)
    slot = workspace == WORKSPACE_A ? "a1" : "b1"
    name = world[:credentials].fetch([ provider, slot ])[:name]
    # Some providers list their models only once they have asked their upstream.
    deadline = Time.now + 60
    loop do
      models = client.models_for(name)
      found = models.find { |id| id.start_with?("#{workspace}/") }
      return found if found
      flunk("#{provider} lists no model for its workspace: #{models.inspect}\n#{world[:proxy].logs}") if Time.now > deadline

      Kernel.sleep 1
    end
  end

  # Sends every request at once, since the proxy waits between retry rounds on a failing upstream.
  def burst(workspace, text: nil, cache_key: nil, rounds: 2)
    requests = PROVIDERS.flat_map do |provider|
      model = model_for(provider, workspace)
      Array.new(rounds) { [ model, text || "question #{SecureRandom.hex(6)}" ] }
    end
    requests.flat_map do |model, words|
      [ Thread.new { client.chat(model, words, cache_key:) }, Thread.new { client.respond(model, words, cache_key:) } ]
    end.map(&:value).tap { |responses| warn responses.map { |response| "#{response.code} #{response.body.to_s[0, 300]}" }.uniq.join("\n") if ENV["ISOLATION_DEBUG"] }
  end

  def owners(hits)
    by_port = world[:credentials].values.to_h { |credential| [ credential[:port], credential[:workspace] ] }
    hits.map { |hit| by_port.fetch(hit[:port], :unclaimed) }
  end

  def assert_only_reached(workspace, hits, context)
    strangers = hits.reject { |hit| ports_of(workspace).include?(hit[:port]) }
    assert_empty strangers, "#{context} reached a credential that is not its workspace's: #{strangers.inspect}\n#{world[:proxy].logs}"
  end

  def assert_every_provider_reached(hits, workspace)
    PROVIDERS.each do |provider|
      assert hits.any? { |hit| ports_of(workspace, provider).include?(hit[:port]) }, "#{provider} never reached its upstream for #{workspace}"
    end
  end

  def test_a_each_workspace_reaches_only_its_own_credentials_through_failover
    [ WORKSPACE_A, WORKSPACE_B ].each do |workspace|
      upstream.drain
      responses = burst(workspace)
      refute responses.any? { |response| response.is_a?(Net::HTTPSuccess) }, "a failing upstream answered"
      hits = upstream.drain
      assert_every_provider_reached(hits, workspace)
      assert_only_reached workspace, hits, workspace
    end
  end

  def test_b_several_credentials_of_one_workspace_take_turns
    upstream.drain
    burst(WORKSPACE_A, rounds: 3)
    hits = upstream.drain
    PROVIDERS.each do |provider|
      reached = ports_of(WORKSPACE_A, provider).select { |port| hits.any? { |hit| hit[:port] == port } }
      assert_equal 2, reached.size, "#{provider} did not use both of workspace A's credentials"
    end
  end

  def test_c_the_same_conversation_in_two_workspaces_stays_apart
    text = "You are Halon. The same first message in every workspace."
    [ WORKSPACE_A, WORKSPACE_B, WORKSPACE_A ].each do |workspace|
      upstream.drain
      burst(workspace, text:, cache_key: "shared-session", rounds: 1)
      assert_only_reached workspace, upstream.drain, "the shared conversation in #{workspace}"
    end
  end

  # Sign-ins go through the proxy's own Codex sign-in, its token exchange answered by the stub the container's outbound
  # traffic goes to. What they made is removed afterwards, so later tests' requests never reach a credential with no
  # stub of its own.
  def with_sign_ins
    yield
  ensure
    client.credentials.select { |file| file["note"].to_s != "" }.each { |file| client.delete(file.fetch("name")) }
  end

  # The proxy shows what a sign-in saved a moment after the sign-in says it finished: the credential, its note, then
  # its models. Each read waits for the state it is about, then is checked once.
  def listed
    60.times do
      found = yield
      return found unless found.nil? || found == []

      Kernel.sleep 0.25
    end
    yield
  end

  def credential_for(sign_in_id) = listed { client.credentials.find { |file| file["note"] == sign_in_id } }

  # Two credentials of one kind saved at the same moment can leave one listed with no models registered, until the
  # credential is next changed. Firefight's claim changes it (SubscriptionProxy::SignIns, a credential with no models),
  # and so does this, before reading the models it then checks every one of.
  def served_only_for?(file, workspace)
    client.patch_fields(file.fetch("name"), { priority: 1 })
    ids = listed { client.models_for(file.fetch("name")) }
    ids.any? && ids.all? { |id| id.start_with?("#{workspace}/") }
  end

  def test_d_two_workspaces_signing_in_at_once_each_get_exactly_their_own_credential
    with_sign_ins do
      mine = SecureRandom.uuid
      theirs = SecureRandom.uuid
      state_mine = client.start_sign_in(sign_in_id: mine, workspace: WORKSPACE_A)
      state_theirs = client.start_sign_in(sign_in_id: theirs, workspace: WORKSPACE_B)
      [ Thread.new { client.finish_sign_in(state_mine, "ana-#{SecureRandom.hex(3)}") },
        Thread.new { client.finish_sign_in(state_theirs, "ben-#{SecureRandom.hex(3)}") } ].each(&:join)

      assert_equal [ "ok", "ok" ], [ client.settled(state_mine), client.settled(state_theirs) ], world[:proxy].logs
      a = credential_for(mine)
      b = credential_for(theirs)
      assert a && b, "each sign-in's credential carries its own id: #{client.credentials.map { |file| [ file['name'], file['note'] ] }}"
      refute_equal a.fetch("name"), b.fetch("name")
      assert served_only_for?(a, WORKSPACE_A), -> { "A's credential serves only A: #{client.models_for(a.fetch("name")).inspect} #{a.slice("name", "note", "status", "status_message").inspect}\n#{world[:proxy].logs}" }
      assert served_only_for?(b, WORKSPACE_B), -> { "B's credential serves only B: #{client.models_for(b.fetch("name")).inspect} #{b.slice("name", "note", "status", "status_message").inspect}\n#{world[:proxy].logs}" }
    end
  end

  def test_e_the_same_login_signed_in_from_another_workspace_is_refused_and_the_first_keeps_it
    with_sign_ins do
      login = "carol-#{SecureRandom.hex(3)}"
      first = SecureRandom.uuid
      state = client.start_sign_in(sign_in_id: first, workspace: WORKSPACE_A)
      client.finish_sign_in(state, login)
      assert_equal "ok", client.settled(state)
      owned = credential_for(first)

      second = SecureRandom.uuid
      state = client.start_sign_in(sign_in_id: second, workspace: WORKSPACE_B)
      client.finish_sign_in(state, login)
      assert_match(/Failed to save/, client.settled(state), "the proxy refused to save it")
      assert_equal "taken", client.refusal(second)
      assert_nil credential_for(second)
      kept = client.credentials.find { |file| file["name"] == owned.fetch("name") }
      assert_equal first, kept.fetch("note")
      assert served_only_for?(kept, WORKSPACE_A), "B's sign-in left A's credential with A"

      again = SecureRandom.uuid
      state = client.start_sign_in(sign_in_id: again, workspace: WORKSPACE_A)
      client.finish_sign_in(state, login)
      assert_equal "ok", client.settled(state), "the same login signed in again in its own workspace is a reconnect"
      assert_equal owned.fetch("name"), credential_for(again).fetch("name")
      assert_equal({ "refused" => "", "credential" => owned.fetch("name"), "workspace" => WORKSPACE_A }, client.sign_in_result(again))
    end
  end

  # The proxy names a ChatGPT credential by its plan too, so the same login on another plan is another file name.
  def test_e2_the_same_login_on_another_plan_is_still_one_login
    with_sign_ins do
      login = "dana-#{SecureRandom.hex(3)}"
      first = SecureRandom.uuid
      state = client.start_sign_in(sign_in_id: first, workspace: WORKSPACE_A)
      client.finish_sign_in(state, "#{login}~plus")
      assert_equal "ok", client.settled(state)
      owned = credential_for(first).fetch("name")

      elsewhere = SecureRandom.uuid
      state = client.start_sign_in(sign_in_id: elsewhere, workspace: WORKSPACE_B)
      client.finish_sign_in(state, "#{login}~pro")
      assert_match(/Failed to save/, client.settled(state))
      assert_equal "taken", client.refusal(elsewhere)
      assert_nil credential_for(elsewhere)

      again = SecureRandom.uuid
      state = client.start_sign_in(sign_in_id: again, workspace: WORKSPACE_A)
      client.finish_sign_in(state, "#{login}~pro")
      assert_equal "ok", client.settled(state)
      mine = listed { client.credentials.select { |file| file["email"] == "#{login}@example.com" }.then { |found| found if found.any? { |file| file["note"] == again } } }
      assert_equal [ owned ], Array(mine).map { |file| file["name"] }, "signed in again on another plan, it replaces its credential rather than adding one"
      assert_equal again, mine.first.fetch("note")
    end
  end

  def test_e3_the_same_login_signed_in_from_two_workspaces_at_once_is_connected_to_one
    with_sign_ins do
      login = "erin-#{SecureRandom.hex(3)}"
      mine = SecureRandom.uuid
      theirs = SecureRandom.uuid
      state_mine = client.start_sign_in(sign_in_id: mine, workspace: WORKSPACE_A)
      state_theirs = client.start_sign_in(sign_in_id: theirs, workspace: WORKSPACE_B)
      [ Thread.new { client.finish_sign_in(state_mine, login) }, Thread.new { client.finish_sign_in(state_theirs, login) } ].each(&:join)

      outcomes = [ client.settled(state_mine), client.settled(state_theirs) ]
      assert_equal 1, outcomes.count("ok"), outcomes.inspect
      saved = listed { client.credentials.select { |file| file["email"] == "#{login}@example.com" } }
      assert_equal 1, saved.size, -> { [ client.sign_in_result(mine), client.sign_in_result(theirs), client.credentials.map { |file| file.slice("name", "email", "note") } ].inspect }
      winner = outcomes.first == "ok" ? [ mine, WORKSPACE_A ] : [ theirs, WORKSPACE_B ]
      assert_equal winner, [ saved.first.fetch("note"), client.sign_in_result(winner.first).fetch("workspace") ]
      assert_equal "taken", client.refusal(winner.first == mine ? theirs : mine)
    end
  end

  def test_f_a_cancelled_sign_in_approved_late_saves_nothing
    with_sign_ins do
      cancelled = SecureRandom.uuid
      state = client.start_sign_in(sign_in_id: cancelled, workspace: WORKSPACE_A)
      client.cancel_sign_in(state)

      late = client.finish_sign_in(state, "late-#{SecureRandom.hex(3)}")

      refute late.is_a?(Net::HTTPSuccess), "the proxy took a cancelled sign-in's code"
      Kernel.sleep 2
      assert_nil credential_for(cancelled)
    end
  end

  def test_g_a_sign_in_firefight_did_not_name_saves_nothing
    with_sign_ins do
      before = client.credentials.map { |file| file["name"] }
      state = client.start_sign_in
      client.finish_sign_in(state, "nameless-#{SecureRandom.hex(3)}")

      assert_match(/Failed to save/, client.settled(state), "the proxy refused to save it")
      assert_equal before.sort, client.credentials.map { |file| file["name"] }.sort, "no credential without a workspace's prefix is ever saved"
    end
  end

  def test_y_an_exhausted_workspace_never_borrows_another_workspaces_subscription
    ports_of(WORKSPACE_A).each { |port| upstream.set_mode(port, :exhausted) }
    upstream.drain
    responses = burst(WORKSPACE_A)
    refute responses.any? { |response| response.is_a?(Net::HTTPSuccess) }, "workspace A was answered with its own subscriptions exhausted"
    hits = upstream.drain
    assert_every_provider_reached(hits, WORKSPACE_A)
    assert_only_reached WORKSPACE_A, hits, "exhausted A"

    upstream.drain
    burst(WORKSPACE_A)
    assert_only_reached WORKSPACE_A, upstream.drain, "A again while exhausted"
  ensure
    ports_of(WORKSPACE_A).each { |port| upstream.set_mode(port, :unavailable) }
  end

  # Runs after the rest, since it removes workspace A's credentials.
  def test_zz_a_workspace_with_no_subscription_reaches_nobody_elses
    models = PROVIDERS.to_h { |provider| [ provider, model_for(provider, WORKSPACE_A) ] }
    unclaimed_ports = PROVIDERS.to_h do |provider|
      %w[a1 a2].each do |slot|
        credential = world[:credentials].fetch([ provider, slot ])
        client.delete(credential[:name])
        credential[:deleted] = true
      end
      # A sign-in that has finished but that Firefight has not yet given to a workspace has no prefix.
      name = "#{provider}-unclaimed-#{SecureRandom.hex(3)}.json"
      port = upstream.open_port
      client.upload(name, SubscriptionProxyIsolation.credential(provider, "#{provider}-unclaimed", port))
      [ provider, port ]
    end
    upstream.drain

    responses = models.values.flat_map do |model|
      [ Thread.new { client.chat(model, "nothing of mine #{SecureRandom.hex(4)}") }, Thread.new { client.respond(model, "nothing of mine #{SecureRandom.hex(4)}") } ]
    end.map(&:value)
    refute responses.any? { |response| response.is_a?(Net::HTTPSuccess) }, "a workspace with no subscription was answered"
    assert_empty upstream.drain, "a workspace with no subscription reached another credential"

    models.each do |provider, model|
      client.chat(model.split("/", 2).last, "unprefixed #{SecureRandom.hex(4)}")
      hits = upstream.drain
      assert hits.all? { |hit| hit[:port] == unclaimed_ports.fetch(provider) }, "#{provider} served an unprefixed request with a workspace's credential: #{hits.inspect}"
    end
  end
end
