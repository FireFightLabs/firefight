require "application_system_test_case"

# Halon places each chart in its answer with a marker, and the chat draws the chart there, live and once saved.
class AgentInlineChartsTest < ApplicationSystemTestCase
  STARTED = Time.utc(2026, 9, 25, 14, 0)

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.ask!("How is memory on web and the job?")
    @chat = @conversation.chat_record
  end

  test "charts sit where the answer places them, adjacent ones side by side, an unknown marker shows nothing, and an unplaced one follows" do
    web, job, cpu = drawn("call_1", "Memory of web", "Memory of job", "CPU of web")
    answered("Memory climbed on both at 14:40.\n\n#{marker(web)}\n#{marker(job)}\n\nThe job came back down. {{chart:00000000}}\n\nNothing else moved.")

    visit agent_chat_path(@conversation)

    assert_text(/Memory climbed on both at 14:40\..*Memory of web.*Memory of job.*The job came back down\..*Nothing else moved\..*CPU of web/m)
    assert_no_text "{{chart"
    assert_selector "figure", count: 3
    assert_equal top(web.title), top(job.title), "adjacent charts share a row"
    assert_operator left(job.title), :>, left(web.title)
    assert_operator top(cpu.title), :>, top(web.title)
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-inline-charts-wide.png"))

    page.current_window.resize_to(390, 844)
    assert_operator top(job.title), :>, top(web.title), "on a phone the row stacks"
    assert_equal left(web.title), left(job.title)
    assert_equal 0, page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-inline-charts-phone.png"))
  end

  test "a chart named twice is drawn once, where it was first placed" do
    web, = drawn("call_1", "Memory of web")
    answered("Web climbed.\n\n#{marker(web)}\n\nAs the same chart shows:\n\n#{marker(web)}")

    visit agent_chat_path(@conversation)

    assert_text(/Web climbed\..*Memory of web.*As the same chart shows:/m)
    assert_selector "figure", count: 1
    assert_operator top("Memory of web"), :<, text_top("As the same chart shows:")
  end

  test "a marker in a code block stays code" do
    web, = drawn("call_1", "Memory of web")
    answered("Write it like this:\n\n````\n```\n#{marker(web)}\n````\n\nAnd this:\n\n```\n~~~\n#{marker(web)}\n```")

    visit agent_chat_path(@conversation)

    assert_selector "pre", text: marker(web), count: 2
    assert_selector "figure", count: 1
  end

  test "a line of backticks with a backtick after them opens no code block, so a marker after it still places its chart" do
    web, = drawn("call_1", "Memory of web")
    answered("```sh`ell is not a fence.\n\nWeb climbed.\n\n#{marker(web)}\n\nIt came back down.")

    visit agent_chat_path(@conversation)

    assert_text(/Web climbed\..*Memory of web.*It came back down\./m)
    assert_no_selector "pre", text: marker(web)
  end

  test "a live answer draws a chart as soon as its marker arrives, and the words after it never move it" do
    cable_async!
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))
    # The call is saved as the turn makes it, before its answer is written.
    web, job = drawn("call_1", "Memory of web", "Memory of job")
    visit agent_chat_path(@conversation)
    assert_text "How is memory"
    delivery = Conversation::LiveDelivery.new(@conversation)
    open_stream(delivery)
    metrics = Chat::Tools::Step.new(title: "Query metrics", headline: "", asked: [], card: Chat::Tools.chart_card)
    delivery.step(key: "call_1", step: metrics, status: :running)
    delivery.step(key: "call_1", step: metrics, status: :done)

    said(delivery, "Memory climbed on both at 14:40.\n\n#{marker(web)[0, 7]}")
    assert_text "Memory climbed on both at 14:40."
    assert_no_text "{{"
    assert_no_selector "figure"

    said(delivery, "#{marker(web)[7..]}\n#{marker(job)}\n\nThe job ")
    assert_selector "figure[aria-label='Memory of web']"
    assert_selector "figure[aria-label='Memory of job']"
    placed = top("Memory of web")
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-inline-charts-live.png"))

    said(delivery, "came back down.\n\nNothing else moved, and this line runs long enough to wrap onto a second line on a phone.")
    assert_text "Nothing else moved"
    assert_equal placed, top("Memory of web"), "words after a chart never push it"
    assert_text(/Memory climbed on both at 14:40\..*Memory of web.*The job came back down\./m)
    live_text = page.find("body").text
    page.current_window.resize_to(390, 844)
    assert_operator top("Memory of job"), :>, top("Memory of web")
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-inline-charts-live-phone.png"))
    page.current_window.resize_to(1400, 1400)

    answered("Memory climbed on both at 14:40.\n\n#{marker(web)}\n#{marker(job)}\n\nThe job came back down.\n\nNothing else moved, and this line runs long enough to wrap onto a second line on a phone.")
    delivery.answered!("ignored")
    visit agent_chat_path(@conversation)

    assert_text "Nothing else moved"
    assert_selector "figure", count: 2
    assert_equal live_text.gsub(/\s+/, " ").scan(/Memory climbed.*?Nothing else moved/), page.find("body").text.gsub(/\s+/, " ").scan(/Memory climbed.*?Nothing else moved/),
                 "a reload reads as the live answer did"
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-inline-charts-finished.png"))
  ensure
    cable_restore!
  end

  test "a chart drawn while the answer is still being written but placed nowhere waits for the turn to end" do
    cable_async!
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))
    drawn("call_1", "Memory of web")
    visit agent_chat_path(@conversation)
    assert_text "How is memory"
    delivery = Conversation::LiveDelivery.new(@conversation)
    open_stream(delivery)
    metrics = Chat::Tools::Step.new(title: "Query metrics", headline: "", asked: [], card: Chat::Tools.chart_card)
    delivery.step(key: "call_1", step: metrics, status: :done)
    said(delivery, "Memory climbed at 14:40.")

    assert_text "Memory climbed at 14:40."
    assert_no_selector "figure"

    answered("Memory climbed at 14:40.")
    delivery.answered!("ignored")

    assert_selector "figure[aria-label='Memory of web']"
    assert_operator top("Memory of web"), :>, text_top("Memory climbed at 14:40.")
  ensure
    cable_restore!
  end

  private

  def drawn(tool_call_id, *titles)
    reply = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: "northflank_query_metrics", arguments: { "resource" => "web" })
    @chat.add_message(role: :tool, content: "Memory of web", tool_call_id: tool_call_id)
    Chat::Chart.record!(@chat, tool_call_id, titles.map do |title|
      { "title" => title, "unit" => "MB", "from" => STARTED.iso8601, "to" => (STARTED + 59.minutes).iso8601,
        "link" => "https://app.northflank.com/t/acme/project/shop/services/web",
        "series" => [ { "label" => "#{title.split.last}-1", "points" => (0..59).map { |minute| [ (STARTED + minute.minutes).iso8601, 200 + (minute > 40 ? 300 : minute) ] } } ] }
    end)
  end

  def answered(text)
    @conversation.note!(text)
    @conversation.reply_delivered!
  end

  def marker(chart) = Chat::Chart::Marker.for(chart)

  # Words go out in pieces a moment apart, so each piece is sent once its moment has passed. Travel drops the fraction of
  # a second, so it moves on by more than the moment.
  def said(delivery, text)
    travel 2.seconds
    delivery.chunk(text)
  end

  def top(title) = rect("figure[aria-label='#{title}']")["top"]

  def left(title) = rect("figure[aria-label='#{title}']")["left"]

  def text_top(text)
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".agent-answer p")).find((node) => node.textContent.includes(#{text.to_json})).getBoundingClientRect().top + window.scrollY
    JS
  end

  def rect(selector)
    find(selector)
    page.evaluate_script("(() => { const box = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return { top: Math.round(box.top + window.scrollY), left: Math.round(box.left) } })()")
  end

  # The test adapter only records broadcasts, and a live answer needs the browser to receive them.
  def cable_async!
    @cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.restart
  end

  def cable_restore!
    return unless @cable

    ActionCable.server.config.cable = @cable
    ActionCable.server.restart
  end

  # An accepted subscription can miss what is sent before its stream is live, and a turn already owed shows Working
  # without it, so a first step is announced until the page shows it.
  def open_stream(delivery)
    brief = Chat::Tools::Step.new(title: "Read the brief", headline: "", asked: [], card: nil)
    50.times do
      delivery.step(key: "call_0", step: brief, status: :running)
      next unless page.has_text?("Read the brief", wait: 0.2)

      return delivery.step(key: "call_0", step: brief, status: :done)
    end

    flunk "the page never opened its socket"
  end
end
