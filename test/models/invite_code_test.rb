require "test_helper"

class InviteCodeTest < ActiveSupport::TestCase
  test "redeem! raises when invite was already redeemed" do
    invite_code = invite_codes(:active_public_beta_code)

    InviteCode.where(id: invite_code.id).update_all(redeemed_at: Time.current)

    assert_raises(InviteCode::RedemptionError) do
      invite_code.redeem!(users(:charlie))
    end
  end

  test "find_active_by_code is case- and whitespace-insensitive" do
    expected = invite_codes(:active_public_beta_code)

    assert_equal expected, InviteCode.find_active_by_code("BETA-ACCESS")
    assert_equal expected, InviteCode.find_active_by_code("beta-access")
    assert_equal expected, InviteCode.find_active_by_code("  BETA-ACCESS  ")
    assert_equal expected, InviteCode.find_active_by_code("BeTa-AcCeSs")
  end

  test "find_active_by_code returns nil for expired or redeemed codes" do
    assert_nil InviteCode.find_active_by_code("EXPIRED-BETA")
    assert_nil InviteCode.find_active_by_code("USED-BETA")
  end
end
