require "test_helper"

class InviteCodeTest < ActiveSupport::TestCase
  fixtures :users, :invite_codes

  test "redeem! raises when invite was already redeemed" do
    invite_code = invite_codes(:active_public_beta_code)

    InviteCode.where(id: invite_code.id).update_all(redeemed_at: Time.current)

    assert_raises(InviteCode::RedemptionError) do
      invite_code.redeem!(users(:charlie))
    end
  end
end
