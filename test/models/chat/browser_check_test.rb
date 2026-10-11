require "test_helper"

class Chat::BrowserCheckTest < ActiveSupport::TestCase
  test "an address without a scheme opens over https on both screen sizes, and the path is kept as asked" do
    check = Chat::BrowserCheck.from({ "url" => "shop.example.com/cart", "steps" => [ { "action" => "click", "text" => " Checkout ", "extra" => "x" } ] })

    assert_equal "https://shop.example.com/cart", check.url
    assert_equal %w[desktop phone], check.viewports
    assert_equal [ { "action" => "click", "text" => "Checkout" } ], check.steps
    assert_equal "shop.example.com", check.host
    assert_not check.sends?
  end

  test "only http and https, no credentials in the address, and a step needs what it finds its target by" do
    assert_raises_with("Only http and https") { Chat::BrowserCheck.from({ "url" => "javascript:alert(1)" }) }
    assert_raises_with("Only http and https") { Chat::BrowserCheck.from({ "url" => "file:///etc/passwd" }) }
    assert_raises_with("Leave the user name and password out") { Chat::BrowserCheck.from({ "url" => "https://me:secret@shop.example.com" }) }
    assert_raises_with("needs text, label, or role and name") { from_steps([ { "action" => "click" } ]) }
    assert_raises_with("needs a key") { from_steps([ { "action" => "press", "key" => "rm -rf" } ]) }
    assert_raises_with("needs a url") { from_steps([ { "action" => "goto" } ]) }
    assert_raises_with("Only http and https") { from_steps([ { "action" => "goto", "url" => "ftp://shop.example.com" } ]) }
    assert_raises_with("has no action") { from_steps([ { "action" => "download" } ]) }
    assert_raises_with("not a screen size") { Chat::BrowserCheck.from({ "url" => "https://shop.example.com", "viewports" => [ "watch" ] }) }
  end

  test "only a click, typing or a key press can be sent, a send runs on one screen size, and a run that only reads never sends" do
    steps = [ { "action" => "wait_for_text", "text" => "Newsletter" }, { "action" => "click", "text" => "Subscribe" } ]
    check = Chat::BrowserCheck.from({ "url" => "https://shop.example.com", "steps" => steps, "send_step" => 2 })

    assert check.sends?
    assert_equal [ "desktop" ], check.viewports
    assert_raises_with("sends nothing") { Chat::BrowserCheck.from({ "url" => "https://shop.example.com", "steps" => steps, "send_step" => 1 }) }
    assert_raises_with("not one of the steps") { Chat::BrowserCheck.from({ "url" => "https://shop.example.com", "steps" => steps, "send_step" => 3 }) }
    assert_raises_with("only reads") { Chat::BrowserCheck.from({ "url" => "https://shop.example.com", "steps" => steps, "send_step" => 2 }, sends_allowed: false) }
  end

  test "the digest ties a send to the look the person was shown, whatever the screen sizes, and the pages are capped" do
    look = Chat::BrowserCheck.from({ "url" => "https://shop.example.com", "steps" => [ { "action" => "click", "text" => "Pay" } ] })
    sending = Chat::BrowserCheck.from({ "url" => "https://shop.example.com", "steps" => [ { "action" => "click", "text" => "Pay" } ], "send_step" => 1 })
    other = Chat::BrowserCheck.from({ "url" => "https://shop.example.com", "steps" => [ { "action" => "click", "text" => "Buy" } ] })

    assert_equal look.digest, sending.digest
    assert_not_equal look.digest, other.digest
    assert_equal 4, look.planned_pages
    many = Chat::BrowserCheck.from({ "url" => "https://shop.example.com", "steps" => Array.new(12) { { "action" => "click", "text" => "Next" } } })
    assert_equal 2 * Chat::BrowserCheck::PAGES_PER_VIEWPORT, many.planned_pages
  end

  private

  def from_steps(steps) = Chat::BrowserCheck.from({ "url" => "https://shop.example.com", "steps" => steps })

  def assert_raises_with(words, &)
    assert_match words, assert_raises(Chat::BrowserCheck::Refused, &).message
  end
end
