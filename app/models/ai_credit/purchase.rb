# What setup offers to buy with Firefight credits, from the hosted build's answer (Entitlements.ai_credit), with the AI
# the plan includes every month, or else the starter credit a new workspace was given, and roughly what it buys said in
# words. The markup only shapes the estimate and never reaches the browser. Nil where credits are not sold.
module AiCredit::Purchase
  # What one chat answer cost on the default model at list price, measured by the chat bench on Claude Sonnet 5.5 at
  # about $0.09 a scenario. It only says roughly what a balance buys and never charges anything.
  AVERAGE_ANSWER_MICROS = 90_000
  MICROS_PER_DOLLAR = 1_000_000

  def self.for(workspace, return_to:)
    offer = Entitlements.ai_credit(workspace).try(:purchase, return_to: return_to)
    return nil unless offer

    included = offer[:includedMicros].to_i
    amount = included.positive? ? included : offer[:starterMicros].to_i
    note = included.positive? ? included_note(included) : starter_note(amount)
    offer.except(:starterMicros, :includedMicros, :markupPercent).merge(
      note: (note if amount.positive?),
      estimate: (estimate(amount, offer[:markupPercent].to_i) if amount.positive?)
    )
  end

  # "Includes $10 to get started. Buy more any time."
  def self.starter_note(micros) = "Includes #{dollars(micros)} to get started. Buy more any time."

  # "Your plan includes $25 of AI every month. Buy more any time."
  def self.included_note(micros) = "Your plan includes #{dollars(micros)} of AI every month. Buy more any time."

  # "As a rough guide, $10 is about 90 questions to Halon.", from the average answer with the markup on top.
  def self.estimate(micros, markup_percent)
    answers = micros / (AVERAGE_ANSWER_MICROS * (100 + markup_percent) / 100.0)
    answers = answers >= 20 ? (answers / 10).round * 10 : [ answers.round, 1 ].max
    "As a rough guide, #{dollars(micros)} is about #{answers} #{answers == 1 ? 'question' : 'questions'} to Halon."
  end

  # "$10", or "$12.50" when there are cents.
  def self.dollars(micros)
    cents = micros / (MICROS_PER_DOLLAR / 100)
    (cents % 100).zero? ? "$#{cents / 100}" : format("$%.2f", cents / 100.0)
  end
end
