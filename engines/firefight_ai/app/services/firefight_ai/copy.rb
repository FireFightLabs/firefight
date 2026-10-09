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
    RULE = [ PUNCTUATION, PEOPLE, QUOTING ].join(" ").freeze
  end
end
