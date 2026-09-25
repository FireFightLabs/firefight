require "test_helper"

class Operator::CredentialTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @credential = Operator::Credential.start_for!(@user)
  end

  test "an operator is a user named in OPERATOR_USER_IDS, and nobody else" do
    with_operators(@user.id) do
      assert Operator::Credential.operator?(@user)
      assert_not Operator::Credential.operator?(users(:bob))
      assert_not Operator::Credential.operator?(nil)
    end
    assert_not Operator::Credential.operator?(@user)
  end

  test "setup keeps one secret until it is confirmed, and confirming hands back recovery codes once" do
    assert_equal @credential.totp_secret, Operator::Credential.start_for!(@user).totp_secret

    codes = @credential.confirm!(current_code)

    assert_equal Operator::Credential::RECOVERY_CODE_COUNT, codes.size
    assert @credential.reload.confirmed?
    assert_not_includes @credential.recovery_code_digests, codes.first
  end

  test "a code works once, even the same code a moment later" do
    @credential.confirm!(current_code)
    travel 31.seconds do
      code = current_code
      assert @credential.reload.verify!(code)
      assert_not @credential.reload.verify!(code)
    end
  end

  test "a recovery code works once" do
    codes = @credential.confirm!(current_code)

    assert @credential.verify!(codes.first.upcase)
    assert_not @credential.reload.verify!(codes.first)
    assert_equal Operator::Credential::RECOVERY_CODE_COUNT - 1, @credential.recovery_codes_left
  end

  test "five wrong codes lock the factor, even to the right code, until the lock runs out" do
    @credential.confirm!(current_code)

    Operator::Credential::MAX_FAILED_ATTEMPTS.times { @credential.reload.verify!("000000") }

    assert @credential.reload.locked?
    travel 31.seconds do
      assert_not @credential.reload.verify!(current_code)
    end
    travel Operator::Credential::LOCKOUT + 1.minute do
      assert @credential.reload.verify!(current_code)
    end
  end

  private

  def current_code = ROTP::TOTP.new(@credential.totp_secret).now

  def with_operators(ids)
    previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = ids
    yield
  ensure
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = previous
  end
end
