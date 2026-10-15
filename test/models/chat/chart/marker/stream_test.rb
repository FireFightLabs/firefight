require "test_helper"

class Chat::Chart::Marker::StreamTest < ActiveSupport::TestCase
  test "a marker split across chunks never shows, and the line it stood on goes with it" do
    assert_equal "Memory of web climbed.\n\nThe job held steady.",
                 streamed("Memory of web climbed.\n\n{{cha", "rt:3f9a", "1c2e}}\n{{chart:9b2c4d1a}}", "\n\nThe job held steady.")
  end

  test "a marker inside a sentence is dropped as it arrives" do
    assert_equal "Memory of web climbed.", streamed("Memory of web climbed {{chart:", "3f9a1c2e}}", ".")
  end

  test "text that only looked like a marker's start is let through" do
    assert_equal "Templates read {{ name }} here.", streamed("Templates read {", "{ name }} here.")
  end

  test "text arrives as soon as nothing in it could be a marker" do
    shown = []
    stream = Chat::Chart::Marker::Stream.new { |text| shown << text }

    stream.add("Memory of web ")
    stream.add("climbed {{ch")

    assert_equal [ "Memory of web ", "climbed" ], shown
  end

  test "a marker that ends the answer leaves nothing behind" do
    assert_equal "Memory of web climbed.\n\n", streamed("Memory of web climbed.\n\n", "{{chart:3f9a1c2e}}")
  end

  test "an answer without markers streams exactly as written" do
    assert_equal "One  \ntwo\n\n\n\nthree {", streamed("One  \ntwo\n\n", "\n\nthree {")
  end

  private

  def streamed(*chunks)
    shown = +""
    stream = Chat::Chart::Marker::Stream.new { |text| shown << text }
    chunks.each { |chunk| stream.add(chunk) }
    stream.finish
    shown
  end
end
