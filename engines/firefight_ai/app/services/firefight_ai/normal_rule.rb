module FirefightAi
  # An error a service has printed every day for months reads as alarming in an incident's logs, and is usually not
  # what broke. This holds in a chat and a run.
  module NormalRule
    RULE = "A log pattern seen all week is not the cause by itself. new_log_patterns says which kinds of line a resource " \
           "did not print in the last week and which of its error patterns are usual. Lean on what is new or changed, " \
           "such as a new pattern, a reading run_key_query puts above normal, or a deploy, and name a usual pattern as the " \
           "cause only when something shows it changed.".freeze
  end
end
