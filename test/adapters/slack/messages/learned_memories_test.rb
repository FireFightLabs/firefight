require "test_helper"

class Slack::Messages::LearnedMemoriesTest < ActiveSupport::TestCase
  Shown = MemoryPostService::Shown
  Memory = MemoryPostService::ShownMemory

  test "a lesson waiting for a person carries Confirm, Not right and Correct, each naming the post and the memory" do
    blocks = build(Chat::MemoryPost::KIND_INCIDENT, memory(Chat::Memory::STATE_UNCONFIRMED))

    assert_equal ":brain:  *What Halon learned from INC-007*", blocks.first.dig(:text, :text)
    assert_equal "divider", blocks.second[:type]
    actions = blocks.find { |block| block[:type] == "actions" }[:elements]
    assert_equal [ "Confirm", "Not right", "Correct" ], actions.map { |button| button.dig(:text, :text) }
    assert_equal [ Identifiers::MEMORY_CONFIRM, Identifiers::MEMORY_REJECT, Identifiers::MEMORY_CORRECT ], actions.map { |button| button[:action_id] }
    assert(actions.all? { |button| button[:value] == "post-1:memory-1" })
    assert_equal "context", blocks.last[:type], "the footer says what to do while something waits"
  end

  test "a disputed or outdated memory says where it stands and offers Still right, never a plain Confirm" do
    disputed = build(Chat::MemoryPost::KIND_DISPUTED, memory(Chat::Memory::STATE_DISPUTED, reason: "The resolver answered fine"))

    assert_equal ":grey_question:  *Halon disputed a memory*", disputed.first.dig(:text, :text)
    assert_includes context_text(disputed), "Disputed. The resolver answered fine. Halon stopped using it until someone decides."
    assert_equal [ "Still right", "Not right", "Correct" ], buttons(disputed)
    assert_equal [ "Still right", "Not right", "Correct" ], buttons(build(Chat::MemoryPost::KIND_INCIDENT, memory(Chat::Memory::STATE_OUTDATED, reason: "web was renamed api")))
    assert_equal [ "Confirm", "Not right", "Correct" ], buttons(build(Chat::MemoryPost::KIND_INCIDENT, memory(Chat::Memory::STATE_EXPIRED, reason: "Nobody confirmed it within 30 days.")))
  end

  test "a decided memory says who decided and carries no buttons, and a correction shows what Halon remembers now" do
    confirmed = build(Chat::MemoryPost::KIND_POSTMORTEM, memory(Chat::Memory::STATE_CONFIRMED, decided_by: "a postmortem"))
    corrected = build(Chat::MemoryPost::KIND_INCIDENT, memory(Chat::Memory::STATE_REJECTED, decided_by: "Ada", correction: "The cause was the <pool>"))

    assert_equal ":brain:  *What Halon learned from the INC-007 postmortem*", confirmed.first.dig(:text, :text)
    assert_includes context_text(confirmed), ":white_check_mark: Confirmed by a postmortem"
    assert_empty buttons(confirmed)
    assert_includes context_text(corrected), ":pencil2: Corrected by Ada. Halon now remembers this instead. The cause was the &lt;pool&gt;"
    assert_not_includes context_text(corrected), Slack::Messages::LearnedMemories::LESSONS, "nothing waits, so nothing asks"
  end

  test "what a model wrote is escaped, a removed subject says so, and every memory deleted leaves a line saying why the message is empty" do
    blocks = build(Chat::MemoryPost::KIND_LEARNED, memory(Chat::Memory::STATE_UNCONFIRMED, text: "<!channel> uses *bold*", about: "web", about_removed: true))

    assert_equal "&lt;!channel&gt; uses *bold*", blocks.third.dig(:text, :text)
    assert_includes context_text(blocks), "About web, which is no longer on the map"
    assert_includes context_text(build(Chat::MemoryPost::KIND_INCIDENT)), "Someone deleted these on the Memory page."
  end

  test "a reminder says how many wait and why confirming matters, and links the Memory page" do
    ENV.stubs(:[]).returns(nil)
    ENV.stubs(:[]).with("APP_HOST").returns("firefight.test")
    blocks = Slack::Messages::LearnedMemories.build(Shown.new(post_id: "post-1", kind: Chat::MemoryPost::KIND_REMINDER, incident_identifier: nil,
                                                              memories: [ memory(Chat::Memory::STATE_UNCONFIRMED), memory(Chat::Memory::STATE_UNCONFIRMED) ],
                                                              reminder: MemoryPostService::ShownReminder.new(taught: 2, learned: 0, direct: true)))

    assert_equal ":bell:  *Memories nobody confirmed yet*", blocks.first.dig(:text, :text)
    assert_equal "Halon picked up 2 things from your chats that nobody has confirmed yet. Confirming keeps them in use, and anything wrong stops Halon repeating it.",
                 blocks.third.dig(:text, :text)
    assert_equal [ "Confirm", "Not right", "Correct" ] * 2, buttons(blocks)
    assert_equal "Everything waiting is on the <https://firefight.test/app/memory|Memory page>.", blocks.last[:elements].first[:text]
  end

  test "a reminder names an incident in its channel, and an admin is told why they are asked" do
    channel = intro(MemoryPostService::ShownReminder.new(taught: 0, learned: 1, direct: false))
    admin = intro(MemoryPostService::ShownReminder.new(taught: 0, learned: 3, direct: true))
    both = intro(MemoryPostService::ShownReminder.new(taught: 1, learned: 2, direct: true))

    assert_equal "Halon picked up 1 thing from INC-007 that nobody has confirmed yet. Confirming keeps it in use, and if it is wrong Halon stops repeating it.", channel
    assert_equal "Halon picked up 3 things from incidents and investigations that nobody has confirmed yet. You are asked as a workspace admin, since no " \
                 "incident channel is left to ask in. Confirming keeps them in use, and anything wrong stops Halon repeating it.", admin
    assert_match "Halon picked up 1 thing from your chats, and 2 from incidents and investigations, that nobody has confirmed yet.", both
  end

  private

  def memory(state, text: "Sessions live in Redis", about: nil, about_removed: false, reason: nil, decided_by: nil, correction: nil)
    Memory.new(id: "memory-1", text: text, about: about, about_removed: about_removed, state: state, reason: reason, decided_by: decided_by, correction: correction)
  end

  def build(kind, *memories) = Slack::Messages::LearnedMemories.build(Shown.new(post_id: "post-1", kind: kind, incident_identifier: "INC-007", memories: memories))

  def intro(reminder)
    Slack::Messages::LearnedMemories.intro(Shown.new(post_id: "post-1", kind: Chat::MemoryPost::KIND_REMINDER, incident_identifier: "INC-007", memories: [],
                                                     reminder: reminder))
  end

  def buttons(blocks) = blocks.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements].map { |button| button.dig(:text, :text) } }

  def context_text(blocks) = blocks.select { |block| block[:type] == "context" }.flat_map { |block| block[:elements].map { |element| element[:text] } }.join("\n")
end
