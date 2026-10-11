module FirefightAi
  # How Halon writes what a person reads, the same rules Firefight's own copy follows.
  module Copy
    PUNCTUATION = "Write with full stops, commas and parentheses, and leave out em dashes and semicolons.".freeze
    # Seen in a real change, a question called the person "he" from nothing but their name.
    PEOPLE = "Call a person by their name, or use they and them, rather than pronouns guessed from a name.".freeze
    # Seen in a real change, "Never silently create another workspace" came back as "You asked that signup never create
    # another workspace", a rule stricter than what was written.
    QUOTING = "When you give a person's own words as a reason, quote them exactly and in quotes, as strict or as loose " \
              "as they wrote them.".freeze
    # Where a check that could not run is listed, in a pull request and in what Halon says about it.
    NOT_RUN_HEADING = "Could not run here".freeze
    # Seen in a real change, tests that could not start for want of a Postgres extension were listed under Blocked,
    # which read as if the change had not been made.
    NOT_RUN = "A check or test that could not run, such as tests that need a database or an extension the sandbox lacks, " \
              "goes under #{NOT_RUN_HEADING} with why. Blocked is only for something that stopped the work itself.".freeze
    # How every prompt that writes for a person writes.
    WRITING = [ PUNCTUATION, PEOPLE, QUOTING ].join(" ").freeze
    # For a prompt that may also report on checks, such as a code change's write-up or a review.
    RULE = [ WRITING, NOT_RUN ].join(" ").freeze
  end
end
