require "test_helper"

class CleanupIdempotencyKeysJobTest < ActiveSupport::TestCase
  test "deletes stale idempotency keys" do
    stale = idempotency_keys(:stale_key)
    recent = idempotency_keys(:existing_key)

    CleanupIdempotencyKeysJob.perform_now

    assert_not IdempotencyKey.exists?(stale.id)
    assert IdempotencyKey.exists?(recent.id)
  end
end
