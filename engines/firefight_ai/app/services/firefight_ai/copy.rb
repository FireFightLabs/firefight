module FirefightAi
  # How Halon writes what a person reads, the same rules Firefight's own copy follows.
  module Copy
    PUNCTUATION = "Never use em dashes or semicolons in what you write. Use a full stop, a comma or parentheses instead.".freeze
    # Seen in a real change, a question called the person "he" from nothing but their name.
    PEOPLE = "Never guess anyone's pronouns from their name. Call a person by their name, or use they and them.".freeze
    # Seen in a real change, "Never silently create another workspace" came back as "You asked that signup never create
    # another workspace", a rule stricter than what was written.
    QUOTING = "When you give a person's own words as a reason, quote them exactly and in quotes. Never reword them into " \
              "something stricter or looser than what they wrote.".freeze
    # Where a check that could not run is listed, in a pull request and in what Halon says about it.
    NOT_RUN_HEADING = "Could not run here".freeze
    # Seen in a real change, tests that could not start for want of a Postgres extension were listed under Blocked,
    # which read as if the change had not been made.
    NOT_RUN = "A check or test that could not run, such as tests that need a database or an extension the sandbox lacks, " \
              "goes under #{NOT_RUN_HEADING} with why. Never call it blocked or a blocker, and never list it under a Blocked " \
              "heading. Blocked means something stopped the work itself.".freeze
    RULE = [ PUNCTUATION, PEOPLE, QUOTING, NOT_RUN ].join(" ").freeze
  end
end
