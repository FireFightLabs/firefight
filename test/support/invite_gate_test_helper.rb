module InviteGateTestHelper
  # The gate is off by default. Tests that exercise the invite-code path turn
  # it on for their own duration. Mocha unstubs after each test.
  def require_invite!
    InviteCode.stubs(:required?).returns(true)
  end
end
