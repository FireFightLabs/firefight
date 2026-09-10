module InviteGateTestHelper
  # The gate is off by default, tests turn it on for their own duration.
  def require_invite!
    InviteCode.stubs(:required?).returns(true)
  end
end
