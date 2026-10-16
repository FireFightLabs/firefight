import { usePage } from "@inertiajs/react"

import { AgentSteps } from "@/components/agent-chat/agent-steps"
import { PlacedAnswer } from "@/components/agent-chat/placed-answer"
import { ChartGrid } from "@/components/charts/chart-grid"
import { chartsOfTurn, placeCharts } from "@/lib/agent-chat/chart-markers"
import { PART_KINDS, turnParts, workUnderWay } from "@/lib/agent-chat/work-parts"
import { OPEN_WINDOW, type TurnPiece, type TurnWindow } from "@/lib/agent-chat/types"
import type { SharedProps } from "@/types"
import type { ChatChart } from "@/types/serializers"

interface TurnStoryProps {
  pieces: TurnPiece[]
  // The turn is still being written.
  live: boolean
  // What a coding agent's question or pause reloads on the page showing the chat.
  reloads: string[]
  // When the turn began and the next question came, so only the charts it drew are drawn in it.
  window?: TurnWindow
}

// Halon's turn in the order it happened. Its work folds once done, and what it said to the person, a question or the
// turn's result, stays where it was said and never folds with it. A chart the turn drew sits where Halon placed it in
// its words, and one it placed nowhere follows them once the turn is done.
export function TurnStory({ pieces, live, reloads, window = OPEN_WINDOW }: TurnStoryProps) {
  const { charts } = usePage<SharedProps & { charts?: ChatChart[] }>().props
  const parts = turnParts(pieces)
  const underWay = live ? workUnderWay(parts) : null
  const said = parts.flatMap((part) => (part.kind === PART_KINDS.SAID ? [ part.text ] : []))
  const placed = placeCharts(said, chartsOfTurn(pieces, charts ?? [], window), live)

  return (
    <>
      {parts.map((part) => (part.kind === PART_KINDS.WORK
        ? <AgentSteps key={part.id} pieces={part.pieces} underWay={part.id === underWay} reloads={reloads} />
        : <PlacedAnswer key={part.text.id} segments={placed.segments.get(part.text.id) ?? []} />))}
      {!live && placed.unplaced.length > 0 && <ChartGrid charts={placed.unplaced} />}
    </>
  )
}
