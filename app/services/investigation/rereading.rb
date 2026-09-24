# Reads each claim of an answer against what its cited steps returned before it is published, and drops one they do not
# show. A check that cannot run keeps every claim, since dropping them would be our failure passed off as theirs.
class Investigation::Rereading
  Result = Data.define(:kept, :dropped)
  Dropped = Data.define(:claim, :reason)

  def initialize(investigation)
    @investigation = investigation
  end

  # evidence is as the agent gave it to conclude, one item per claim, already checked to cite real steps.
  def check(evidence)
    items = Array(evidence).map { |item| item.to_h.stringify_keys }
    verdicts = judge(items).index_by(&:number)

    kept, dropped = items.each_with_index.partition { |_item, index| verdicts[index + 1]&.shown != false }
    Result.new(
      kept: kept.map(&:first),
      dropped: dropped.map { |item, index| Dropped.new(claim: item["claim"].to_s, reason: verdicts[index + 1].reason) }
    )
  end

  private

  def judge(items)
    claims = items.each_with_index.map do |item, index|
      FirefightAi::CitationCheck::Claim.new(number: index + 1, text: item["claim"].to_s, steps: Array(item["steps"]).map(&:to_i).uniq)
    end
    checker.check(claims: claims, sources: sources(claims.flat_map(&:steps).uniq))
  rescue FirefightAi::Error => error
    Rails.logger.warn({ event: "investigation.reread_failed", investigation_id: @investigation.id, error: error.message }.to_json)
    []
  end

  def sources(numbers)
    @investigation.steps.where(position: numbers, status: Investigation::Step::STATUS_SUCCEEDED).map do |step|
      FirefightAi::CitationCheck::Source.new(step: step.position, tool: step.tool_name, text: step.raw_result.presence || step.compacted_result.to_s)
    end
  end

  def checker
    FirefightAi::CitationCheck.new(
      @investigation.workspace, inferable: @investigation,
      member: (@investigation.triggered_by if @investigation.triggered_by.is_a?(WorkspaceMembership))
    )
  end
end
