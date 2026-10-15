require "test_helper"

class Investigation::FindingTest < ActiveSupport::TestCase
  test "an answer reads as plain text everywhere, and keeps where Halon placed its charts for the dashboard" do
    finding = Investigation::Finding.new(summary: "Memory of web climbed.\n\n{{chart:3f9a1c2e}}\n\nThe pool filled.", gaps: "Could not read {{chart:9b2c4d1a}} the job.")

    assert_equal "Memory of web climbed.\n\nThe pool filled.", finding.summary
    assert_equal "Could not read the job.", finding.gaps
    assert_equal "Memory of web climbed.\n\n{{chart:3f9a1c2e}}\n\nThe pool filled.", finding.placed_summary
  end
end
