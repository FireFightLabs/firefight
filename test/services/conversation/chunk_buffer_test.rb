require "test_helper"

class Conversation::ChunkBufferTest < ActiveSupport::TestCase
  test "a space already found inside an open link is not tried again as more text arrives" do
    buffer = Conversation::ChunkBuffer.new(interval: 0, max_chars: 1, whole_markup: true) { |_text| nil }
    buffer.add("[the pull request that")
    tried = []
    buffer.define_singleton_method(:closed?) { |text| tried << text.length && false }
    buffer.add(" fixes")

    assert_equal [ "[the pull request that ".length ], tried
  end

  test "a link is never cut across two pieces, and the words before it go as soon as they are due" do
    sent = []
    buffer = Conversation::ChunkBuffer.new(interval: 1.hour, max_chars: 10, whole_markup: true) { |text| sent << text }

    buffer.add("Opened [PR #856](https://github.com/")
    buffer.add("acme/app/pull/856) for")
    buffer.add(" it.")
    buffer.flush!

    assert_equal [ "Opened ", "[PR #856](https://github.com/acme/app/pull/856) ", "for it." ], sent
  end

  test "bold, inline code and a code block go whole" do
    sent = []
    buffer = Conversation::ChunkBuffer.new(interval: 1.hour, max_chars: 5, whole_markup: true) { |text| sent << text }

    buffer.add("**two words** and `a b` then\n```\nputs 1\n")
    buffer.add("```\n")

    assert_equal [ "**two words** and `a b` then\n", "```\nputs 1\n```\n" ], sent
  end

  test "text that never closes what it opened goes as it is once it grew long" do
    sent = []
    buffer = Conversation::ChunkBuffer.new(interval: 1.hour, max_chars: 5, whole_markup: true) { |text| sent << text }

    buffer.add("[#{'word ' * Conversation::ChunkBuffer::LONG_HELD}")

    assert_equal 1, sent.size
  end

  test "without whole markup, text goes as soon as it is due, as before" do
    sent = []
    buffer = Conversation::ChunkBuffer.new(interval: 1.hour, max_chars: 10) { |text| sent << text }

    buffer.add("Opened [PR #856](https://github.com/")

    assert_equal [ "Opened [PR #856](https://github.com/" ], sent
  end
end
