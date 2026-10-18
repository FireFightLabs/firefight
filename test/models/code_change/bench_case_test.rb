require "test_helper"

class CodeChange::BenchCaseTest < ActiveSupport::TestCase
  test "every code fix scenario loads, says what broke and what to change, and its diff applies to its files" do
    scenarios = CodeChange::BenchCase.scenarios

    assert_equal 4, scenarios.size
    scenarios.each do |scenario|
      assert scenario.shape.present?, "#{scenario.key} says nothing about the incident it comes from"
      assert scenario.brief.present?, "#{scenario.key} has no brief"
      assert_equal "larkspur/shop", scenario.repository
      assert scenario.expected.any?, "#{scenario.key} expects no change"
      [ scenario.title, scenario.shape, scenario.brief ].each { |text| refute_match(/[—;]/, text, "#{scenario.key}: #{text}") }
    end
  end

  test "the chat bench never reads a code fix scenario as one of its own" do
    refute Conversation::BenchCase.scenarios.any? { |scenario| scenario.key.in?(CodeChange::BenchCase.scenarios.map(&:key)) }
  end

  test "a diff that changes a file the scenario does not hold is refused" do
    error = assert_raises(CodeChange::BenchCase::Invalid) do
      CodeChange::BenchCase.from_hash(scenario_data(expected_diff: <<~DIFF), key: "broken")
        --- a/app/models/missing.rb
        +++ b/app/models/missing.rb
        @@ -1,1 +1,1 @@
        -old
        +new
      DIFF
    end

    assert_equal "The expected diff changes app/models/missing.rb, which files does not hold.", error.message
  end

  test "a diff whose lines are not in the file is refused, and a new file needs no lines" do
    error = assert_raises(CodeChange::BenchCase::Invalid) do
      CodeChange::BenchCase.from_hash(scenario_data(expected_diff: <<~DIFF), key: "broken")
        --- a/app/models/order.rb
        +++ b/app/models/order.rb
        @@ -1,2 +1,2 @@
         class Order
        -  def nothing_like_this
        +  def total
      DIFF
    end
    assert_equal "The expected diff does not apply to app/models/order.rb, since the lines of its hunk at line 1 are not in the file.", error.message

    created = CodeChange::BenchCase.from_hash(scenario_data(expected_diff: <<~DIFF), key: "created")
      --- /dev/null
      +++ b/test/models/order_test.rb
      @@ -0,0 +1,2 @@
      +class OrderTest
      +end
    DIFF
    assert_equal [ "test/models/order_test.rb" ], created.expected.keys
  end

  test "a scenario with no diff or no files is refused with the field it lacks" do
    error = assert_raises(CodeChange::BenchCase::Invalid) { CodeChange::BenchCase.from_hash(scenario_data(expected_diff: ""), key: "empty") }
    assert_equal "expected_diff is missing.", error.message

    error = assert_raises(CodeChange::BenchCase::Invalid) { CodeChange::BenchCase.from_hash(scenario_data.merge("files" => {}), key: "empty") }
    assert_equal "files is missing.", error.message
  end

  private

  def scenario_data(expected_diff: nil)
    {
      "title" => "A test", "shape" => "Something broke.", "repository" => "larkspur/shop", "brief" => "Fix it.",
      "files" => { "app/models/order.rb" => "class Order\n  def total\n  end\nend\n" },
      "expected_diff" => expected_diff
    }
  end
end
