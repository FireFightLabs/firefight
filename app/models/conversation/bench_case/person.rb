# What the person in a scenario wants, stated once for the whole chat, and how they answer a question Halon asks in
# plain words rather than on a card, such as "Shall I open the pull request?". approves and refuses are patterns for
# what they agree to and turn down when Halon offers it, answers are replies to questions only they can answer, and
# otherwise is what they say to any other question. The answer comes only from what the scenario states, so two replays
# of one scenario hear the same reply to the same question.
class Conversation::BenchCase::Person < Data.define(:approves, :refuses, :answers, :otherwise)
  YES = "Yes, go ahead.".freeze
  NO = "No, leave that as it is for now.".freeze

  # A sentence that ends in a question mark.
  QUESTION = /[^.!?\n]*\?/
  # A question offering to do something, which a yes or a no answers.
  OFFER = /\b(shall|should) (i|we)\b|\b(do|would) you (want|like)\b|\bwant me to\b|\b(can|may|could) i\b|\b(ok|okay|alright) (if|to)\b|\bgo ahead\b|\blike me to\b/i

  def self.none = new(approves: [], refuses: [], answers: [], otherwise: nil)

  # What the person says to Halon's reply during a turn, or nil when it asks nothing they would answer. The turn's own
  # words come first, then the whole chat's, then for an offer the turn's next card decision (decisions are those not
  # yet given), then what they say to anything else.
  def answer(reply, turn:, decisions:)
    asked = reply.to_s.scan(QUESTION).map(&:strip).compact_blank.join(" ")
    return if asked.empty?

    replied(turn.answers, asked) || verdict(turn, asked) || replied(answers, asked) || verdict(self, asked) ||
      (decided(decisions.first) if asked.match?(OFFER)) || otherwise
  end

  private

  def replied(replies, asked) = replies.find { |reply| Conversation::BenchCase.mentions?([ reply.asked ], asked) }&.say

  # A refusal wins over an agreement, so a scenario that wants a no always hears it.
  def verdict(stated, asked)
    return NO if Conversation::BenchCase.mentions?(stated.refuses, asked)

    YES if Conversation::BenchCase.mentions?(stated.approves, asked)
  end

  def decided(decision)
    { Conversation::BenchCase::DECISION_APPROVE => YES, Conversation::BenchCase::DECISION_DENY => NO }[decision]
  end
end
