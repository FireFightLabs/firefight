module SubscriptionProxy
  # One claim or sweep at a time for each kind of sign-in across the install, so two workspaces never claim from the same
  # list and the sweep never removes a credential being claimed. The lock is a session's own, on a connection of its
  # own, so no transaction stays open while the proxy answers.
  module ClaimLock
    ASK_EVERY = 0.2

    # Yields and answers the block's value once held, or answers BUSY without yielding when not held within wait.
    BUSY = :busy

    def self.hold(proxy, wait:)
      holder = SubscriptionSignIn.connection_pool.db_config.new_connection
      asked = SubscriptionSignIn.sanitize_sql([ "SELECT pg_try_advisory_lock(hashtextextended(?, 0))", "subscription_sign_in:#{proxy}" ])
      deadline = wait.from_now
      until holder.select_value(asked) == true
        return BUSY if Time.current > deadline

        Kernel.sleep ASK_EVERY
      end
      yield
    ensure
      holder&.disconnect!
    end
  end
end
