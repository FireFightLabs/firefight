module Slack
  module Messages
    # Memories an incident's channel is asked to decide on, which the incident or its postmortem taught, or which a chat
    # or run working on it learned or disputed, and the weekly reminder of what nobody confirmed, in a channel or to one
    # person. Each memory carries the buttons its state allows, and a decided one says who decided.
    module LearnedMemories
      TITLES = {
        Chat::MemoryPost::KIND_INCIDENT => ":brain:  *What Halon learned from %<incident>s*",
        Chat::MemoryPost::KIND_POSTMORTEM => ":brain:  *What Halon learned from the %<incident>s postmortem*",
        Chat::MemoryPost::KIND_LEARNED => ":brain:  *Halon learned something about your setup*",
        Chat::MemoryPost::KIND_DISPUTED => ":grey_question:  *Halon disputed a memory*",
        Chat::MemoryPost::KIND_REMINDER => ":bell:  *Memories nobody confirmed yet*"
      }.freeze
      LESSONS = "Halon already uses these, marked unconfirmed. Confirm the ones that are right, and mark the rest not right so it stops using them.".freeze
      FOOTERS = {
        Chat::MemoryPost::KIND_INCIDENT => LESSONS,
        Chat::MemoryPost::KIND_POSTMORTEM => LESSONS,
        Chat::MemoryPost::KIND_LEARNED => "Halon already uses this, marked unconfirmed. Confirm it if it is right, or mark it not right so it stops using it.",
        Chat::MemoryPost::KIND_DISPUTED => "Something Halon read contradicted this, so it stopped using it. Say whether it still holds.",
        Chat::MemoryPost::KIND_REMINDER => "Everything waiting is on the Memory page."
      }.freeze
      # Where the team's memories in a reminder came from, as its opening line names them.
      TEAM_SOURCES = "incidents and investigations".freeze
      # A memory in one of these still waits for a person, so it carries buttons.
      WAITING = [ Chat::Memory::STATE_UNCONFIRMED, Chat::Memory::STATE_OUTDATED, Chat::Memory::STATE_DISPUTED, Chat::Memory::STATE_EXPIRED ].freeze
      # A memory Halon stopped trusting is confirmed as still right, not as something new.
      STILL_RIGHT = [ Chat::Memory::STATE_OUTDATED, Chat::Memory::STATE_DISPUTED ].freeze

      # post is a MemoryPostService::Shown.
      def self.build(post)
        [
          { type: "section", text: { type: "mrkdwn", text: title(post) } },
          { type: "divider" },
          (intro_block(post) if post.reminder),
          *(post.memories.empty? ? [ gone ] : post.memories.flat_map { |memory| memory_blocks(post.post_id, memory) }),
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

      def self.title(post) = format(TITLES.fetch(post.kind), incident: post.incident_identifier)

      def self.footer(post) = { type: "context", elements: [ { type: "mrkdwn", text: footer_text(post) } ] }

      # A reminder links the Memory page when the dashboard's address is known.
      def self.footer_text(post)
        url = Slack::DashboardUrl.memory if post.reminder
        url ? "Everything waiting is on the <#{url}|Memory page>." : FOOTERS.fetch(post.kind)
      end

      def self.gone = { type: "context", elements: [ { type: "mrkdwn", text: "Someone deleted these on the Memory page." } ] }

      # The memory came from a model or a person, so it is escaped like any other outside text.
      def self.memory_blocks(post_id, memory)
        [
          { type: "section", text: { type: "mrkdwn", text: Slack::Mrkdwn.escape(memory.text) } },
          { type: "context", elements: [ { type: "mrkdwn", text: [ about(memory), standing(memory) ].compact.join("  ·  ") } ] },
          (actions(post_id, memory) if WAITING.include?(memory.state))
        ].compact
      end

      def self.about(memory)
        return "About the whole workspace" if memory.about.blank?

        "About #{Slack::Mrkdwn.escape(memory.about)}#{', which is no longer on the map' if memory.about_removed}"
      end

      # Where the memory stands, said in words, so a disputed or outdated one never reads as if it were live.
      def self.standing(memory)
        by = " by #{Slack::Mrkdwn.escape(memory.decided_by)}" if memory.decided_by
        case memory.state
        when Chat::Memory::STATE_CONFIRMED then ":white_check_mark: Confirmed#{by}"
        when Chat::Memory::STATE_REJECTED
          return ":no_entry_sign: Marked not right#{by}" unless memory.correction

          ":pencil2: Corrected#{by}. Halon now remembers this instead. #{Slack::Mrkdwn.escape(memory.correction)}"
        when Chat::Memory::STATE_DISPUTED then [ ":grey_question: Disputed.", reason(memory), "Halon stopped using it until someone decides." ].compact.join(" ")
        when Chat::Memory::STATE_OUTDATED then [ ":warning: Possibly outdated.", reason(memory), "Halon still uses it, flagged." ].compact.join(" ")
        when Chat::Memory::STATE_EXPIRED then [ ":hourglass: Expired.", reason(memory), "Halon stopped using it." ].compact.join(" ")
        end
      end

      # Why it stands where it does, as a sentence of its own.
      def self.reason(memory)
        return nil if memory.reason.blank?

        said = Slack::Mrkdwn.escape(memory.reason.strip)
        said.end_with?(".", "!", "?") ? said : "#{said}."
      end

      def self.actions(post_id, memory)
        value = "#{post_id}:#{memory.id}"
        confirm = STILL_RIGHT.include?(memory.state) ? "Still right" : "Confirm"
        { type: "actions", elements: [
          { type: "button", style: "primary", action_id: Identifiers::MEMORY_CONFIRM, text: { type: "plain_text", text: confirm }, value: value },
          { type: "button", action_id: Identifiers::MEMORY_REJECT, text: { type: "plain_text", text: "Not right" }, value: value },
          { type: "button", action_id: Identifiers::MEMORY_CORRECT, text: { type: "plain_text", text: "Correct" }, value: value }
        ] }
      end
    end
  end
end
