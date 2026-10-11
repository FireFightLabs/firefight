# How much Halon's browser may load for a workspace. Every check is ledgered with the most pages it may load, so the
# hour is counted from the ledger, the same rows the activity log shows, and a check that would go past it is refused
# before the sandbox is asked.
module Workspace::Browsing
  extend ActiveSupport::Concern

  PAGES_PER_HOUR = 300
  BROWSER_KEYS = [ Ability::Action::BROWSER_READ, Ability::Action::BROWSER_SUBMIT ].freeze

  def browser_pages_used_this_hour
    Ability::Invocation.where(workspace: self, action_key: BROWSER_KEYS, created_at: 1.hour.ago..)
                       .sum(Arel.sql("COALESCE((params->>'pages')::integer, 0)"))
  end

  def browser_pages_blocked_reason(pages)
    used = browser_pages_used_this_hour
    return if used + pages <= PAGES_PER_HOUR

    "Halon's browser has loaded #{used} of the #{PAGES_PER_HOUR} pages this workspace may load in an hour, and this check could " \
      "load #{pages} more. Check fewer screen sizes or a shorter path, or try again later."
  end
end
