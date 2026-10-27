module Slack
  # One emoji per concept, so two things that mean different things never look alike in a channel. A message names the
  # concept and never writes a shortcode of its own for one listed here.
  module Emoji
    DECLARED = ":rotating_light:".freeze
    UPDATED = ":memo:".freeze
    SUMMARY = ":pencil2:".freeze
    RESOLVED = ":white_check_mark:".freeze
    ACCEPTED = ":ballot_box_with_check:".freeze
    CANCELED = ":wastebasket:".freeze
    REOPENED = ":arrows_counterclockwise:".freeze
    ESCALATED = ":fire_engine:".freeze
    ACKNOWLEDGED = ":ok_hand:".freeze
    REMINDER = ":alarm_clock:".freeze
    ALERT_FIRING = ":red_circle:".freeze
    ALERT_RESOLVED = ":large_green_circle:".freeze
    PAGED = ":pager:".freeze
    APPROVAL = ":lock:".freeze
    PACK_REFUSAL = ":key:".freeze
    LEAD = ":firefighter:".freeze
    SEVERITY = ":fire:".freeze
    STATUS = ":construction:".freeze
    DECLARED_BY = ":mega:".freeze
    CHANNEL = ":speech_balloon:".freeze
    SUBSCRIBE = ":bell:".freeze
    UNSUBSCRIBE = ":no_bell:".freeze
    TEST = ":test_tube:".freeze
    POSTMORTEM = ":clipboard:".freeze
    HALON = ":sparkles:".freeze
    WARNING = ":warning:".freeze
    HIGH_RISK_CHANGE = ":octagonal_sign:".freeze

    # Reactions take the name alone. Halon puts the first on a message it is answering and swaps it for the second once
    # the answer is in.
    REACTION_WORKING = "eyes".freeze
    REACTION_DONE = "heavy_check_mark".freeze
  end
end
