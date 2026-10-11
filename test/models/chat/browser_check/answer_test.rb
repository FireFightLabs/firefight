require "test_helper"

class Chat::BrowserCheck::AnswerTest < ActiveSupport::TestCase
  setup do
    @check = Chat::BrowserCheck.from({ "url" => "https://shop.example.com/cart", "steps" => [ { "action" => "click", "text" => "Pay" } ] })
  end

  test "a page that loaded with every step through and no console errors has no trouble" do
    answer = answer_with("status" => 200, "steps" => [ { "n" => 1, "ok" => true } ],
                         "failed_requests" => [ { "method" => "GET", "url" => "https://shop.example.com/favicon.ico", "status" => 404 } ])

    assert answer.ok?, "a missing icon is not a broken page"
  end

  test "a server error, a console error, a failed step and a request that never answered are each trouble" do
    answer = answer_with("status" => 500, "console" => [ { "type" => "error", "text" => "boom" }, { "type" => "warning", "text" => "meh" } ],
                         "steps" => [ { "n" => 1, "ok" => false, "error" => "Nothing on the page matches \"Pay\"." } ],
                         "failed_requests" => [ { "method" => "POST", "url" => "https://api.example.com/pay", "status" => nil, "error" => "net::ERR_FAILED" } ])

    assert_equal [ "Desktop: the page answered 500.", "Desktop: 1 console error.", "Desktop: step 1 failed, Nothing on the page matches \"Pay\".",
                   "Desktop: 1 request failed or answered with a server error." ], answer.trouble
  end

  test "a stop before something the page would send says what it sends and how Halon asks to send it" do
    answer = answer_with("status" => 200, "stopped" => { "step" => 1, "reason" => "sends_data",
                                                         "would_send" => { "method" => "POST", "url" => "https://shop.example.com/orders",
                                                                           "fields" => [ { "name" => "card", "value" => "[hidden]" } ] } })

    words = answer.words(can_send: true)
    assert_includes words, "Stopped before step 1, since it would send data: POST https://shop.example.com/orders with card=[hidden]. Nothing was sent."
    assert_includes words, "send_step 1"
    assert_includes answer.words(can_send: false), "This run only reads"
  end

  test "a secret is taken out of everything the page said, wherever it is" do
    answer = Chat::BrowserCheck::Answer.new(
      { "viewports" => [ { "name" => "desktop", "page_text" => "hello s3cret", "console" => [ { "type" => "error", "text" => "bad s3cret" } ] } ] },
      check: @check, secrets: [ "s3cret", nil ]
    )

    assert_not_includes answer.words, "s3cret"
    assert_equal "bad [hidden]", answer.viewports.first["console"].first["text"]
  end

  test "an answer the browser could not give is said as it is" do
    answer = Chat::BrowserCheck::Answer.new({ "error" => "Only http and https addresses can be opened." }, check: @check)

    assert_equal [ "The check did not run: Only http and https addresses can be opened." ], answer.trouble
    assert_includes answer.words, "could not check https://shop.example.com/cart"
  end

  private

  def answer_with(viewport)
    Chat::BrowserCheck::Answer.new({ "viewports" => [ { "name" => "desktop", "width" => 1366, "height" => 900 }.merge(viewport) ] }, check: @check, region: "EU")
  end
end
