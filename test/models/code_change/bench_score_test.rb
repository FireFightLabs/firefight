require "test_helper"

class CodeChange::BenchScoreTest < ActiveSupport::TestCase
  test "the expected diff scores full marks on every scenario" do
    CodeChange::BenchCase.scenarios.each do |scenario|
      score = CodeChange::BenchScore.of(scenario, scenario.expected_diff)

      assert_equal 1.0, score.total, "#{scenario.key}: #{score.notes}"
      assert_empty score.notes
    end
  end

  test "an empty diff scores nothing and says it changed nothing" do
    score = CodeChange::BenchScore.of(nil_guard, "")

    assert_equal 0.0, score.total
    assert_includes score.notes, CodeChange::BenchScore::NOTHING_CHANGED
  end

  test "a diff with the right file and half the change scores between, naming the lines it missed" do
    score = CodeChange::BenchScore.of(nil_guard, <<~DIFF)
      --- a/app/services/refunds/notifier.rb
      +++ b/app/services/refunds/notifier.rb
      @@ -6,7 +6,7 @@ module Refunds

           def deliver
      -      email = @refund.order.customer.email
      +      email = @refund.order.customer&.email || @refund.order.guest_email
             RefundMailer.issued(email, @refund.amount).deliver_later
           end
         end
    DIFF

    assert_equal 1.0, score.files
    assert_equal 1.0, score.extra
    assert score.lines.positive? && score.lines < 1.0, "lines scored #{score.lines}"
    assert score.total.between?(0.5, 0.99), "total scored #{score.total}"
    assert_includes score.notes, "1 line of the expected change is missing in app/services/refunds/notifier.rb."
  end

  test "a diff that also changes a file the fix does not need is marked down and the file is named" do
    extra = <<~DIFF
      --- a/config/routes.rb
      +++ b/config/routes.rb
      @@ -1,1 +1,1 @@
      -Rails.application.routes.draw do
      +Rails.application.routes.draw do # touched
    DIFF
    score = CodeChange::BenchScore.of(nil_guard, nil_guard.expected_diff + extra)

    assert_equal 0.5, score.extra
    assert_operator score.total, :<, 1.0
    assert_includes score.notes, "It changed config/routes.rb, which the fix does not need."
  end

  test "lines are compared without regard to the space around them" do
    respaced = nil_guard.expected_diff.gsub("      email =", "  email  =")

    assert_equal 1.0, CodeChange::BenchScore.of(nil_guard, respaced).lines
  end

  private

  def nil_guard = CodeChange::BenchCase.scenario("missing_nil_guard")
end
