import { AnswerText } from "@/components/agent-chat/answer-text"
import { ChartGrid } from "@/components/charts/chart-grid"
import { type AnswerSegment, SEGMENT_KINDS } from "@/lib/agent-chat/chart-markers"

// Halon's words with its charts set in where it placed them (placeCharts).
export function PlacedAnswer({ segments }: { segments: AnswerSegment[] }) {
  return (
    <>
      {segments.map((segment) => (segment.kind === SEGMENT_KINDS.TEXT
        ? <AnswerText key={segment.key} text={segment.text} />
        : <ChartGrid key={segment.key} charts={segment.charts} />))}
    </>
  )
}
