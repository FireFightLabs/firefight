require "test_helper"
require "open3"
require "webrick"

# sandbox/browser_check.mjs in a real browser against pages served here. It needs Node and the Playwright the image pins
# (sandbox/browser/package.json) with its Chromium, installed outside the repository and named by BROWSER_CHECK_MODULES.
# It is skipped on a machine without them, and fails in CI, whose image installs them, so a broken install is never
# passed over in silence.
class BrowserCheckTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("sandbox/browser_check.mjs").to_s
  MODULES = ENV.fetch("BROWSER_CHECK_MODULES", Rails.root.join("sandbox/browser/node_modules").to_s)
  PASSWORD = "correct-horse-7781".freeze
  PINNED = JSON.parse(Rails.root.join("sandbox/browser/package.json").read).dig("dependencies", "playwright")

  setup do
    unless File.directory?(File.join(MODULES, "playwright"))
      missing = "Playwright is not installed. Set BROWSER_CHECK_MODULES to a node_modules holding sandbox/browser's playwright."
      ENV["CI"].present? ? flunk(missing) : skip(missing)
    end
    installed = JSON.parse(File.read(File.join(MODULES, "playwright/package.json")))["version"]
    assert_equal PINNED, installed, "The Playwright in #{MODULES} is not the one sandbox/browser pins."

    @received = Queue.new
    @server = WEBrick::HTTPServer.new(BindAddress: "127.0.0.1", Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    @port = @server.config[:Port]
    pages.each { |path, body| mount(path, body) }
    @server.mount_proc("/missing.png") { |_request, response| response.status = 404 }
    @server.mount_proc("/report.csv") do |_request, response|
      response["Content-Type"] = "text/csv"
      response["Content-Disposition"] = "attachment; filename=report.csv"
      response.body = "a,b\n"
    end
    %w[/order /api/cart /beacon /other /graphql /suggest].each do |path|
      @server.mount_proc(path) do |request, response|
        @received << [ request.request_method, path, request.body.to_s ] unless request.request_method == "OPTIONS"
        response["Access-Control-Allow-Origin"] = "*"
        response.body = "ok"
      end
    end
    @loads = Hash.new(0)
    drifting.each do |path, render|
      @server.mount_proc(path) do |request, response|
        next response.status = 404 unless request.path == path

        response["Content-Type"] = "text/html"
        response.body = render.call(@loads[path] += 1)
      end
    end
    @server.mount_proc("/inside") { |_request, response| response.set_redirect(WEBrick::HTTPStatus::Found, "http://10.255.255.1/admin") }
    @server.mount_proc("/session") do |request, response|
      @received << [ request.request_method, "/session", request.body.to_s ]
      response.set_redirect(WEBrick::HTTPStatus::Found, "/account")
    end
    @serving = Thread.new { @server.start }
  end

  teardown do
    @server&.shutdown
    @serving&.join(5)
  end

  test "a page's console errors, failed requests and timings are reported, with every query string redacted" do
    viewport = check(url: "#{base}/?token=abc123", viewports: %w[desktop]).first

    assert_equal [ 200, "Shop", "#{base}/?[redacted]" ], [ viewport["status"], viewport["title"], viewport["final_url"] ]
    assert(viewport["console"].any? { |entry| entry["type"] == "error" && entry["text"] == "boom here" })
    assert_includes viewport["failed_requests"], { "method" => "GET", "url" => "#{base}/missing.png", "status" => 404, "error" => nil }
    assert viewport["timings_ms"]["load"].is_a?(Integer)
    assert viewport["screenshot"].present?
    assert_not_includes @answer_text, "abc123"
  end

  test "the page is opened on a desktop and a phone screen" do
    viewports = check(url: "#{base}/", viewports: %w[desktop phone])

    assert_equal [ [ "desktop", 1366 ], [ "phone", 412 ] ], viewports.map { |each| [ each["name"], each["width"] ] }
  end

  test "a search form sends nothing, so it runs" do
    viewport = check(url: "#{base}/", steps: [ { action: "fill", placeholder: "Search", value: "shoes" }, { action: "press", placeholder: "Search", key: "Enter" } ]).first

    assert_nil viewport["stopped"]
    assert_equal "#{base}/?[redacted]", viewport["final_url"]
  end

  test "a form that posts stops before it is sent, says what it would send with the password hidden, and the server gets nothing" do
    viewport = check(url: "#{base}/", steps: buying).first

    assert_equal({ "step" => 3, "reason" => "sends_data",
                   "would_send" => { "method" => "POST", "url" => "#{base}/order",
                                     "fields" => [ { "name" => "email", "value" => "a@example.com" }, { "name" => "password", "value" => "[hidden]" } ] } },
                 viewport["stopped"].merge("would_send" => viewport["stopped"]["would_send"].except("digest")))
    assert viewport["screenshot"].present?
    assert_empty received
  end

  test "a click whose script posts to the page's own site is blocked and stops the path" do
    viewport = check(url: "#{base}/", steps: [ { action: "click", text: "Add to cart" }, { action: "expect_text", text: "Welcome" } ]).first

    assert_equal [ "sends_data", "POST", "#{base}/api/cart" ], [ viewport["stopped"]["reason"], *viewport["stopped"]["would_send"].values_at("method", "url") ]
    assert_equal [ { "name" => "item", "value" => "1" } ], viewport["stopped"]["would_send"]["fields"]
    assert_equal 1, viewport["steps"].size
    assert_empty received
  end

  test "a page's own requests while it loads go through whatever their method, and are listed" do
    viewport = check(url: "#{base}/app", steps: [ { action: "wait_for_text", text: "Loaded" } ]).first

    assert_nil viewport["stopped"]
    assert_includes received.map { |method, path, _body| "#{method} #{path}" }, "POST /graphql"
    assert_equal [ "#{base}/graphql", "http://localhost:#{@port}/beacon" ].sort, viewport["load_sends"].map { |each| each["url"] }.sort
    assert_empty viewport["blocked_requests"]
  end

  test "a post a step fires once the page has loaded is never the page's load, so it stops and nothing is sent" do
    viewport = check(url: "#{base}/app", steps: [ { action: "wait_for_text", text: "Loaded" }, { action: "click", text: "Load more" } ]).first

    assert_equal [ "sends_data", 2, "#{base}/graphql" ], [ viewport["stopped"]["reason"], viewport["stopped"]["step"], viewport["stopped"]["would_send"]["url"] ]
    assert_equal [ "{\"query\":\"products\"}" ], received.select { |_method, path, _body| path == "/graphql" }.map(&:last), "only the load's own post arrived"
  end

  test "a page a step opens loads as it does for anyone, and typing that sends stops" do
    opened = check(url: "#{base}/menu", steps: [ { action: "click", text: "Open the app" }, { action: "wait_for_text", text: "Loaded" } ]).first

    assert_nil opened["stopped"]
    assert_equal "#{base}/app", opened["final_url"]
    assert_equal 1, received.count { |_method, path, _body| path == "/graphql" }

    typed = check(url: "#{base}/app", steps: [ { action: "wait_for_text", text: "Loaded" }, { action: "fill", label: "Find", value: "shoes" } ]).first

    assert_equal [ "sends_data", "#{base}/suggest" ], [ typed["stopped"]["reason"], typed["stopped"]["would_send"]["url"] ]
    assert_not(received.any? { |_method, path, _body| path == "/suggest" })
  end

  test "a third party's post is blocked without stopping the path" do
    viewport = check(url: "#{base}/beacon-page", steps: [ { action: "click", text: "Track" }, { action: "expect_text", text: "Tracked page" } ]).first

    assert_nil viewport["stopped"]
    assert(viewport["blocked_requests"].any? { |each| each["url"] == "http://localhost:#{@port}/beacon" })
    assert_empty received
  end

  test "the confirmed step sends exactly what was shown, once" do
    shown = check(url: "#{base}/", steps: buying).first["stopped"]["would_send"]
    viewports = check(url: "#{base}/", viewports: %w[desktop phone], steps: buying, send_step: 3, expected_send: shown)

    assert_equal [ "desktop" ], viewports.map { |each| each["name"] }
    assert_nil viewports.first["stopped"]
    assert_equal [ [ "POST", "/order", "email=a%40example.com&password=hunter22" ] ], received
  end

  test "a confirmed step that would now send something else stops and sends nothing" do
    viewport = check(url: "#{base}/", steps: buying, send_step: 3, expected_send: { method: "POST", url: "#{base}/other" }).first

    assert_equal [ "changed_request", "#{base}/order" ], [ viewport["stopped"]["reason"], viewport["stopped"]["would_send"]["url"] ]
    assert_empty received
  end

  test "what the person is shown carries a fingerprint of the whole request, never its values" do
    shown = check(url: "#{base}/", steps: buying).first["stopped"]["would_send"]

    assert_match(/\A\h{64}\z/, shown["digest"])
    assert_not_includes @answer_text, "hunter22"
  end

  test "a page that changes what its form sends between the look and the send stops, says what it sends now and sends nothing" do
    shown = check(url: "#{base}/drift-body", steps: [ { action: "click", text: "Buy" } ]).first["stopped"]["would_send"]
    assert_equal [ { "name" => "amount", "value" => "1" } ], shown["fields"]

    viewport = check(url: "#{base}/drift-body", steps: [ { action: "click", text: "Buy" } ], send_step: 1, expected_send: shown).first

    assert_equal [ "changed_request", "#{base}/order" ], [ viewport["stopped"]["reason"], viewport["stopped"]["would_send"]["url"] ]
    assert_equal [ { "name" => "amount", "value" => "2" } ], viewport["stopped"]["would_send"]["fields"]
    assert_not_equal shown["digest"], viewport["stopped"]["would_send"]["digest"]
    assert_empty received
  end

  test "a page that changes the query its form sends to between the look and the send stops and sends nothing" do
    shown = check(url: "#{base}/drift-query", steps: [ { action: "click", text: "Buy" } ]).first["stopped"]["would_send"]

    viewport = check(url: "#{base}/drift-query", steps: [ { action: "click", text: "Buy" } ], send_step: 1, expected_send: shown).first

    assert_equal [ "changed_request", "POST", "#{base}/order?[redacted]" ], [ viewport["stopped"]["reason"], *viewport["stopped"]["would_send"].values_at("method", "url") ]
    assert_empty received
  end

  test "a request whose script changes its JSON between the look and the send stops and sends nothing" do
    shown = check(url: "#{base}/drift-json", steps: [ { action: "click", text: "Save" } ]).first["stopped"]["would_send"]

    viewport = check(url: "#{base}/drift-json", steps: [ { action: "click", text: "Save" } ], send_step: 1, expected_send: shown).first

    assert_equal "changed_request", viewport["stopped"]["reason"]
    assert_empty received
  end

  test "the same request sends though its fields come in another order, its JSON keys too, and its anti-forgery token is new" do
    form = check(url: "#{base}/steady", steps: [ { action: "click", text: "Buy" } ]).first["stopped"]["would_send"]
    sent = check(url: "#{base}/steady", steps: [ { action: "click", text: "Buy" } ], send_step: 1, expected_send: form).first

    assert_nil sent["stopped"]
    assert_equal [ "POST", "/order" ], received.sole.first(2)

    json = check(url: "#{base}/steady", steps: [ { action: "click", text: "Save" } ]).first["stopped"]["would_send"]
    saved = check(url: "#{base}/steady", steps: [ { action: "click", text: "Save" } ], send_step: 1, expected_send: json).first

    assert_nil saved["stopped"]
    assert_equal [ "POST", "/api/cart" ], received.sole.first(2)
  end

  test "a saved login signs in first, and the password never comes back, even where the page shows it" do
    viewport = check(url: "#{base}/account", login: { site_url: base, login_url: "#{base}/login", username: "tester", password: PASSWORD }).first

    assert_equal({ "ok" => true, "error" => nil }, viewport["login"])
    assert_includes viewport["page_text"], "Signed in"
    assert_equal [ "POST", "/session" ], received.first.first(2)
    assert_not_includes @answer_text, PASSWORD
    assert_includes viewport["page_text"], "[hidden]"
  end

  test "it says how far it got in the progress file the box names, on each screen, never what it types or a password" do
    Dir.mktmpdir do |dir|
      progress = File.join(dir, "progress.log")
      File.write(progress, "")
      steps = [ { action: "fill", label: "Password", value: "hunter22" }, { action: "fill", placeholder: "Search", value: "shoes" } ]

      run_check({ viewports: %w[desktop phone], private_hosts: %w[127.0.0.1 localhost], url: "#{base}/", steps: steps,
                  login: { site_url: base, login_url: "#{base}/login", username: "tester", password: PASSWORD } },
                env: { "SANDBOX_PROGRESS" => progress })

      reports = File.readlines(progress).map { |line| JSON.parse(line) }
      screens = [ "desktop", "phone" ].flat_map do |screen|
        [ "Logging in", "Opening #{base}/", "Step 1 of 2: Type in the Password field", "Step 2 of 2: Type in the Search field" ].map { |said| "#{said} on the #{screen} screen" }
      end
      assert_equal screens, reports.map { |report| report["message"] }
      assert_equal (0...8).to_a, reports.map { |report| report["value"] }
      assert_equal [ 8 ], reports.map { |report| report["total"] }.uniq
      [ "hunter22", "shoes", PASSWORD ].each { |typed| assert_not_includes File.read(progress), typed }
    end
  end

  test "a private address is refused unless it is allowed" do
    answer = run_check({ url: "#{base}/", private_hosts: [] })

    assert_match "private network", answer["error"]
  end

  test "a redirect to a private address is refused where the browser connects, not only at the first address" do
    viewport = check(url: "#{base}/inside").first

    assert(viewport["blocked_requests"].any? { |each| each["url"].include?("10.255.255.1") && each["reason"].include?("private network") })
    assert_not_equal 200, viewport["status"]
  end

  test "only http and https are opened" do
    answer, status = run_check({ url: "ftp://127.0.0.1/" }, with_status: true)

    assert_equal [ 2, "Only http and https addresses can be opened." ], [ status, answer["error"] ]
  end

  test "a run opens at most its pages" do
    viewport = check(url: "#{base}/", max_pages: 2, steps: [ { action: "goto", url: "/beacon-page" }, { action: "goto", url: "/account" } ]).first

    assert_equal [ 2, "page_cap" ], [ viewport["pages"], viewport["stopped"]["reason"] ]
  end

  test "a download is refused" do
    viewport = check(url: "#{base}/", steps: [ { action: "goto", url: "/report.csv" } ]).first

    assert_equal [ "step_failed", false ], [ viewport["stopped"]["reason"], viewport["steps"].first["ok"] ]
    assert_match "download", viewport["steps"].first["error"]
  end

  private

  def base = "http://127.0.0.1:#{@port}"

  def buying
    [ { action: "fill", label: "Email", value: "a@example.com" }, { action: "fill", label: "Password", value: "hunter22" }, { action: "click", text: "Buy" } ]
  end

  def check(spec)
    answer = run_check({ viewports: %w[desktop], private_hosts: %w[127.0.0.1 localhost] }.merge(spec))
    assert_nil answer["error"]
    answer["viewports"]
  end

  def run_check(spec, with_status: false, env: {})
    stdout, stderr, status = Open3.capture3({ "BROWSER_CHECK_MODULES" => MODULES }.merge(env), "node", SCRIPT,
                                            stdin_data: { deadline_seconds: 60 }.merge(spec).to_json, chdir: Dir.tmpdir)
    @answer_text = stdout
    answer = JSON.parse(stdout.lines.last.to_s)
  rescue JSON::ParserError
    flunk "The script printed no JSON: #{stderr.lines.last(5).join}"
  else
    with_status ? [ answer, status.exitstatus ] : answer
  end

  def received
    taken = []
    taken << @received.pop until @received.empty?
    taken
  end

  def mount(path, body)
    @server.mount_proc(path) do |request, response|
      next response.status = 404 unless request.path == path

      response["Content-Type"] = "text/html"
      response.body = body
    end
  end

  # Pages that render differently on each load, n counting the loads, as a page can between the look and the send.
  def drifting
    {
      "/drift-body" => lambda { |n|
        %(<html><body><form method="post" action="/order"><input type="hidden" name="amount" value="#{n}"><button type="submit">Buy</button></form></body></html>)
      },
      "/drift-query" => lambda { |n|
        %(<html><body><form method="post" action="/order?amount=#{n}"><input type="hidden" name="item" value="1"><button type="submit">Buy</button></form></body></html>)
      },
      "/drift-json" => lambda { |n|
        %(<html><body><button onclick="fetch('/api/cart', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ amount: #{n} }) })">Save</button></body></html>)
      },
      "/steady" => lambda { |n|
        fields = [ %(<input type="hidden" name="item" value="1">), %(<input type="hidden" name="size" value="m">) ]
        json = n.odd? ? "{ item: 1, size: 'm' }" : "{ size: 'm', item: 1 }"
        %(<html><body><form method="post" action="/order">#{n.odd? ? fields.join : fields.reverse.join}) +
          %(<input type="hidden" name="authenticity_token" value="#{SecureRandom.hex(16)}"><button type="submit">Buy</button></form>) +
          %(<button onclick="fetch('/api/cart', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(#{json}) })">Save</button></body></html>)
      }
    }
  end

  def pages
    {
      "/" => <<~HTML,
        <html><head><title>Shop</title></head><body><h1>Welcome</h1><script>console.error("boom here")</script><img src="/missing.png">
        <form method="get" action="/"><input name="q" placeholder="Search"><button>Search</button></form>
        <form method="post" action="/order"><label>Email <input name="email"></label><label>Password <input type="password" name="password"></label><button type="submit">Buy</button></form>
        <button onclick="fetch('/api/cart', { method: 'POST', body: JSON.stringify({ item: 1 }) })">Add to cart</button>
        </body></html>
      HTML
      "/beacon-page" => <<~HTML,
        <html><head><title>Tracked</title></head><body><p>Tracked page</p>
        <button onclick="fetch('http://localhost:#{@port}/beacon', { method: 'POST', body: 'x=1' }).catch(() => {})">Track</button></body></html>
      HTML
      "/app" => <<~HTML,
        <html><head><title>App</title></head><body><p id="state">Loading</p>
        <label>Find <input oninput="fetch('/suggest', { method: 'POST', body: this.value })"></label>
        <button onclick="fetch('/graphql', { method: 'POST', body: 'more' })">Load more</button>
        <script>
          Promise.allSettled([ fetch('/graphql', { method: 'POST', body: '{"query":"products"}' }),
                        fetch('http://localhost:#{@port}/beacon', { method: 'POST', body: 'view=1' }) ])
            .then(() => { document.getElementById('state').textContent = 'Loaded' })
        </script></body></html>
      HTML
      "/menu" => '<html><body><a href="/app">Open the app</a></body></html>',
      "/login" => <<~HTML,
        <html><body><form method="post" action="/session"><label>Username <input name="username"></label>
        <label>Password <input type="password" name="password"></label><button type="submit">Sign in</button></form></body></html>
      HTML
      "/account" => "<html><body><p>Signed in. Your password is #{PASSWORD}.</p></body></html>"
    }
  end
end
