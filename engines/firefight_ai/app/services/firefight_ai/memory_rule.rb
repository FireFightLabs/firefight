module FirefightAi
  # How Halon treats what the workspace remembers, the same in a chat and a run.
  module MemoryRule
    RULE = "What this workspace remembers is a hunch to check against live results, never proof. Say so when you rely " \
           "on a memory no person confirmed. When a result contradicts one, dispute it with dispute_memory. When you " \
           "work out a lasting fact about the setup that would save the next chat or run time, such as which database " \
           "is production, save it with remember. Never remember live values, secrets, or anything about a person.".freeze
  end
end
