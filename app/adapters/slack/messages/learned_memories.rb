module Slack
  module Messages
    # Memories an incident's channel is told about, which the incident or its postmortem taught, or which a chat or run
    # working on it learned or disputed. Nobody is asked to confirm them, since Halon checks each against production every
    # night, so a memory in use carries Not right and Correct for anyone who knows better, and a decided one says who
    # decided. A weekly reminder posted before Halon checked memories itself is still redrawn as it was.
    module LearnedMemories
      TITLES = {
        Chat::MemoryPost::KIND_INCIDENT => ":brain:  *What Halon learned from %<incident>s*",
        Chat::MemoryPost::KIND_POSTMORTEM => ":brain:  *What Halon learned from the %<incident>s postmortem*",
        Chat::MemoryPost::KIND_LEARNED => ":brain:  *Halon learned something about your setup*",
        Chat::MemoryPost::KIND_DISPUTED => ":grey_question:  *Halon disputed a memory*",
        Chat::MemoryPost::KIND_REMINDER => ":bell:  *Memories nobody confirmed yet*",
        Chat::MemoryPost::KIND_CHALLENGED => ":grey_question:  *Halon found evidence against a memory you confirmed*"
      }.freeze
      LESSONS = "Halon already uses these and reviews them against production in its nightly check. If one is wrong, mark it not right or edit it.".freeze
      FOOTERS = {
        Chat::MemoryPost::KIND_INCIDENT => LESSONS,
        Chat::MemoryPost::KIND_POSTMORTEM => LESSONS,
        Chat::MemoryPost::KIND_LEARNED => "Halon already uses this and reviews it against production in its nightly check. If it is wrong, mark it not right or edit it.",
        Chat::MemoryPost::KIND_DISPUTED => "Something Halon read contradicted this, so it stopped using it until its nightly check against production settles it.",
        Chat::MemoryPost::KIND_REMINDER => "Everything waiting is on the Memory page.",
        Chat::MemoryPost::KIND_CHALLENGED => "Halon stopped using it until you decide. Keep it if it is still right, mark it not right, or edit it."
      }.freeze
      # Where the team's memories in a reminder came from, as its opening line names them.
      TEAM_SOURCES = "incidents and investigations".freeze
      # A direct message to the person who approved the lesson Halon found evidence against, in place of the confirmer's words.
      APPROVED_LESSON_TITLE = ":grey_question:  *Halon found evidence against a lesson you approved*".freeze
      # A direct message about a dispute a completed postmortem raised, which names the incident.
      POSTMORTEM_DISAGREES = ":grey_question:  *The %<incident>s postmortem disagrees with %<what>s*".freeze
      APPROVED_LESSON_FOOTER = "Halon and pull request reviews stopped using it until you decide. Keep it if it is still right, mark it not right, or edit it.".freeze
      # A memory in one of these nobody has decided on, so it carries Not right and Correct.
      WAITING = [ Chat::Memory::STATE_UNCONFIRMED, Chat::Memory::STATE_OUTDATED, Chat::Memory::STATE_DISPUTED, Chat::Memory::STATE_EXPIRED ].freeze

      # post is a MemoryPostService::Shown.
      def self.build(post)
        [
          { type: "section", text: { type: "mrkdwn", text: title(post) } },
          { type: "divider" },
          (intro_block(post) if post.reminder),
          *(post.memories.empty? ? [ gone ] : post.memories.flat_map { |memory| memory_blocks(post, memory) }),
          (footer(post) if post.memories.any? { |memory| WAITING.include?(memory.state) })
        ].compact
      end

      def self.fallback(post)
        return "#{plain_title(post)}: #{intro(post)}" if post.reminder

        "#{plain_title(post)}: #{post.memories.map(&:text).join(' ')}"
      end

      def self.plain_title(post) = title(post).gsub(/:[a-z_]+:\s+|\*/, "")

      def self.intro_block(post) = { type: "section", text: { type: "mrkdwn", text: intro(post) } }

      # Such as "Halon picked up 2 things from your chats that nobody has confirmed yet. Confirming keeps them in use, and
      # anything wrong stops Halon repeating it."
      def self.intro(post)
        reminder = post.reminder
        total = reminder.taught + reminder.learned
        picked = if !reminder.direct
          "#{things(total)} from #{post.incident_identifier}"
        elsif reminder.learned.zero?
          "#{things(reminder.taught)} from your chats"
        elsif reminder.taught.zero?
          "#{things(reminder.learned)} from #{TEAM_SOURCES}"
        else
          "#{things(reminder.taught)} from your chats, and #{reminder.learned} from #{TEAM_SOURCES},"
        end
        why = total == 1 ? "Confirming keeps it in use, and if it is wrong Halon stops repeating it." : "Confirming keeps them in use, and anything wrong stops Halon repeating it."
        admin = " You are asked as a workspace admin, since no incident channel is left to ask in." if reminder.direct && reminder.taught.zero?
        "Halon picked up #{picked} that nobody has confirmed yet.#{admin} #{why}"
      end

      def self.things(count) = count == 1 ? "1 thing" : "#{count} things"

      def self.title(post)
        return format(POSTMORTEM_DISAGREES, incident: post.incident_identifier, what: post.approved_lesson ? "a lesson you approved" : "a memory you confirmed") if postmortem_dispute?(post)
        return APPROVED_LESSON_TITLE if post.approved_lesson

        format(TITLES.fetch(post.kind), incident: post.incident_identifier)
      end

      def self.postmortem_dispute?(post) = post.kind == Chat::MemoryPost::KIND_CHALLENGED && post.incident_identifier.present?

      def self.footer(post) = { type: "context", elements: [ { type: "mrkdwn", text: footer_text(post) } ] }

      # A reminder links the Memory page when the dashboard's address is known.
      def self.footer_text(post)
        url = Slack::DashboardUrl.memory if post.reminder
        return "Everything waiting is on the <#{url}|Memory page>." if url
        return APPROVED_LESSON_FOOTER if post.approved_lesson

        FOOTERS.fetch(post.kind)
      end

      def self.gone = { type: "context", elements: [ { type: "mrkdwn", text: "Someone deleted these on the Memory page." } ] }

      # The memory came from a model or a person, so it is escaped like any other outside text.
      def self.memory_blocks(post, memory)
        [
          { type: "section", text: { type: "mrkdwn", text: Slack::Mrkdwn.escape(memory.text) } },
          { type: "context", elements: [ { type: "mrkdwn", text: [ about(memory), standing(memory) ].compact.join("  ·  ") } ] },
          (actions(post, memory) if WAITING.include?(memory.state))
        ].compact
      end

      def self.about(memory)
        return "About the whole workspace" if memory.about.blank?

        "About #{Slack::Mrkdwn.escape(memory.about)}#{', which is no longer on the map' if memory.about_removed}"
      end

      # Where the memory stands, said in words, so a disputed or outdated one never reads as if it were live. An approved
      # lesson in use names who approved it, as a confirmed memory names who confirmed it.
      def self.standing(memory)
        by = " by #{Slack::Mrkdwn.escape(memory.decided_by)}" if memory.decided_by
        approved = ":white_check_mark: Approved by #{Slack::Mrkdwn.escape(memory.approved_by)} for pull request reviews" if memory.approved_by
        case memory.state
        when Chat::Memory::STATE_UNCONFIRMED then approved
        when Chat::Memory::STATE_CONFIRMED
          return approved if approved
          return ":white_check_mark: Checked by Halon against production" if memory.checked_by_halon

          ":white_check_mark: Confirmed#{by}"
        when Chat::Memory::STATE_REJECTED
          return ":no_entry_sign: Marked not right#{by}" unless memory.correction

          ":pencil2: Corrected#{by}. Halon now remembers this instead. #{Slack::Mrkdwn.escape(memory.correction)}"
        when Chat::Memory::STATE_DISPUTED then [ ":grey_question: Disputed.", reason(memory), "Halon stopped using it until its nightly check against production settles it." ].compact.join(" ")
        when Chat::Memory::STATE_OUTDATED then [ ":warning: Possibly outdated.", reason(memory), "Halon still uses it, flagged." ].compact.join(" ")
        when Chat::Memory::STATE_EXPIRED then [ ":hourglass: Expired.", reason(memory), "Halon stopped using it." ].compact.join(" ")
        when Chat::Memory::STATE_MERGED then [ ":link: Merged.", reason(memory), "Halon keeps that one." ].compact.join(" ")
        end
      end

      # Why it stands where it does, as a sentence of its own.
      def self.reason(memory)
        return nil if memory.reason.blank?

        said = Slack::Mrkdwn.escape(memory.reason.strip)
        said.end_with?(".", "!", "?") ? said : "#{said}."
      end

      # Only the person asked about evidence against what they confirmed is offered to keep it, as Still right.
      def self.actions(post, memory)
        value = "#{post.post_id}:#{memory.id}"
        keep = { type: "button", style: "primary", action_id: Identifiers::MEMORY_CONFIRM, text: { type: "plain_text", text: "Still right" }, value: value }
        { type: "actions", elements: [
          (keep if post.kind == Chat::MemoryPost::KIND_CHALLENGED),
          { type: "button", action_id: Identifiers::MEMORY_REJECT, text: { type: "plain_text", text: "Not right" }, value: value },
          { type: "button", action_id: Identifiers::MEMORY_CORRECT, text: { type: "plain_text", text: "Edit" }, value: value }
        ].compact }
      end
    end
  end
end
