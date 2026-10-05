require "test_helper"

module Integrations
  class SentenceTest < ActiveSupport::TestCase
    test "a provider's reason joins Firefight's words as one sentence, never ending twice and never with a semicolon" do
      assert_equal "Jobs could not be read: Northflank answered 403: no access.", Sentence.join("Jobs could not be read", "Northflank answered 403: no access.")
      assert_equal "Jobs could not be read: no access.", Sentence.join("Jobs could not be read", "no access")
      assert_equal "Jobs could not be read.", Sentence.join("Jobs could not be read", " ")
      assert_equal "Could not connect: token expired, sign in again. Reconnect it.", Sentence.join("Could not connect", "token expired; sign in again.", after: "Reconnect it")
      assert_equal "Gone? Really.", Sentence.join("Gone? Really", nil)
      assert_equal "first line only.", Sentence.of(StandardError.new("first line only\nsecond line"))
      assert_nil Sentence.of("")
    end
  end
end
