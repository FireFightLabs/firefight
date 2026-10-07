require "test_helper"

class LoginTokenTest < ActiveSupport::TestCase
  test "only a digest of the token is stored" do
    token = LoginToken.issue!(email: "Person@Example.com")
    login_token = LoginToken.find_by!(token_digest: LoginToken.digest(token))

    assert_equal "person@example.com", login_token.email
    assert_not LoginToken.where(token_digest: token).exists?
    assert_in_delta LoginToken::LIFETIME.from_now, login_token.expires_at, 5.seconds
  end

  test "a token signs in once" do
    token = LoginToken.issue!(email: "person@example.com")

    assert LoginToken.consume(token)
    assert_nil LoginToken.consume(token)
  end

  test "two readers holding the same open token cannot both use it" do
    token = LoginToken.issue!(email: "person@example.com")
    assert LoginToken.find_usable(token)
    assert LoginToken.find_usable(token)

    results = 2.times.map { LoginToken.consume(token) }

    assert_equal 1, results.compact.size
  end

  test "an expired token cannot be used" do
    token = LoginToken.issue!(email: "person@example.com")

    travel LoginToken::LIFETIME + 1.second do
      assert_nil LoginToken.find_usable(token)
      assert_nil LoginToken.consume(token)
    end
  end

  test "using one link closes every other open link for the same address only" do
    first = LoginToken.issue!(email: "person@example.com")
    second = LoginToken.issue!(email: "person@example.com")
    someone_else = LoginToken.issue!(email: "other@example.com")

    assert LoginToken.consume(second)

    assert_nil LoginToken.consume(first)
    assert LoginToken.consume(someone_else)
  end

  test "an unknown or blank token finds nothing" do
    assert_nil LoginToken.find_usable("not-a-token")
    assert_nil LoginToken.find_usable(nil)
    assert_nil LoginToken.consume("")
  end
end

# Real threads need committed rows, so this class runs outside the test transaction and removes what it made.
class LoginTokenConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "many clicks on one link at the same moment sign in exactly once" do
    email = "race-#{SecureRandom.hex(4)}@example.com"
    token = LoginToken.issue!(email: email)
    gate = Concurrent::CountDownLatch.new(1)

    threads = 6.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.wait
          LoginToken.consume(token).present?
        end
      end
    end
    gate.count_down

    assert_equal 1, threads.map(&:value).count(true)
  ensure
    LoginToken.where(email: email).delete_all
  end
end
