module FirefightAi
  # Run through the scenarios a capable SRE meets, Halon found what changed one source at a time, blamed the team's code
  # for timeouts an upstream provider's outage caused, and guessed what a sign-in provider nothing connects had done.
  # All three hold in a chat and a run.
  module OutsideRule
    CHANGED_RULE = "To learn what changed before something broke, call what_changed first for the resource, its service or the " \
                   "whole workspace. It puts deploys and runs, settings the map saw change, edits made by hand at a provider and " \
                   "changes made through Firefight in one list, and says what it could not cover. Read further only where it " \
                   "points.".freeze

    STATUS_RULE = "When errors point outside, such as timeouts, refused connections or 5xx answers from a third party's host, " \
                  "read that provider's status page with check_status_page before blaming the team's own code, and say what " \
                  "it showed with its address. A result whose failing lines name a provider's host already carries its status.".freeze

    BLIND_SPOT_RULE = "When a question needs a system you hold no tool for, such as failed logins while sign-in runs through an " \
                      "outside provider, call blind_spots and say which system it is, where it was seen and how to connect it. " \
                      "Never guess what a system nothing connects did.".freeze
  end
end
