import { stepsOf } from "@/lib/agent-chat/group-turns"
import type { TurnPiece } from "@/lib/agent-chat/types"
import { CHART_MARKER_ARRIVING_PATTERN, CHART_MARKER_PATTERN } from "@/lib/generated/constants"
import type { ChatChart } from "@/types/serializers"

// Halon writes a chart's marker, such as {{chart:3f9a1c2e}}, where the chart belongs in its answer (Chat::Chart::Marker).
// The answer is drawn as its words with the charts set in at their markers, charts on adjacent markers sharing a row.
export const SEGMENT_KINDS = { TEXT: "text", CHARTS: "charts" } as const

export type AnswerSegment =
  | { kind: typeof SEGMENT_KINDS.TEXT; key: string; text: string }
  | { kind: typeof SEGMENT_KINDS.CHARTS; key: string; charts: ChatChart[] }

// What a turn's words came to: each text as its segments, by the text's id, and the charts drawn nowhere in them, which
// follow the answer.
export interface PlacedCharts {
  segments: Map<string, AnswerSegment[]>
  unplaced: ChatChart[]
}

interface PlacedText {
  id: string
  text: string
}

// The start of a marker still arriving, at the very end of the words streamed so far.
const PARTIAL = new RegExp(`(?:${CHART_MARKER_ARRIVING_PATTERN})$`, "i")
const FENCE = /^ {0,3}(```|~~~)/

function markers(): RegExp {
  return new RegExp(CHART_MARKER_PATTERN, "gi")
}

// The charts a turn's own steps drew, a helper's under the step that handed it the check, so a chart is only ever drawn
// in the turn that made it.
export function chartsOfTurn(pieces: TurnPiece[], charts: ChatChart[]): ChatChart[] {
  const keys = new Set(stepsOf(pieces).map((step) => step.key))
  return charts.filter((chart) => keys.has(chart.toolCallId))
}

// Sets each of the turn's charts in at the first marker naming it, across all its texts in order. A marker naming no
// chart of the turn, or one already drawn, is left out. live hides a marker still arriving at the end of the last text.
export function placeCharts(texts: PlacedText[], charts: ChatChart[], live: boolean): PlacedCharts {
  const byHandle = new Map(charts.map((chart) => [ chart.handle.toLowerCase(), chart ]))
  const drawn = new Set<string>()
  const segments = new Map<string, AnswerSegment[]>()
  texts.forEach((entry, index) => {
    const text = live && index === texts.length - 1 ? withoutPartialMarker(entry.text) : entry.text
    segments.set(entry.id, segmentsOf(entry.id, text, byHandle, drawn))
  })
  return { segments, unplaced: charts.filter((chart) => !drawn.has(chart.id)) }
}

// Words with every marker left out, for words that draw no chart, such as a status line among the steps.
export function withoutMarkers(text: string): string {
  return withoutPartialMarker(text).replace(markers(), "")
}

export function withoutPartialMarker(text: string): string {
  return text.replace(PARTIAL, "")
}

function segmentsOf(id: string, text: string, byHandle: Map<string, ChatChart>, drawn: Set<string>): AnswerSegment[] {
  const segments: AnswerSegment[] = []
  const fenced = fencedRanges(text)
  let pending = ""
  let cursor = 0

  function addText(words: string) {
    if (words.trim() !== "") {
      segments.push({ kind: SEGMENT_KINDS.TEXT, key: `${id}:${segments.length}`, text: words })
    }
  }

  for (const match of text.matchAll(markers())) {
    const start = match.index
    if (fenced.some(([ from, to ]) => start >= from && start < to)) {
      continue
    }
    pending += text.slice(cursor, start)
    cursor = start + match[0].length
    const chart = byHandle.get(match[1].toLowerCase())
    if (!chart || drawn.has(chart.id)) {
      continue
    }
    drawn.add(chart.id)
    const last = segments[segments.length - 1]
    if (pending.trim() === "" && last?.kind === SEGMENT_KINDS.CHARTS) {
      last.charts.push(chart)
    } else {
      addText(pending)
      segments.push({ kind: SEGMENT_KINDS.CHARTS, key: `${id}:${segments.length}`, charts: [ chart ] })
    }
    pending = ""
  }
  addText(pending + text.slice(cursor))
  return segments
}

// Where code blocks are, by character, so a marker shown as code stays code.
function fencedRanges(text: string): [number, number][] {
  const ranges: [number, number][] = []
  let offset = 0
  let openedAt: number | null = null
  for (const line of text.split("\n")) {
    if (FENCE.test(line)) {
      if (openedAt === null) {
        openedAt = offset
      } else {
        ranges.push([ openedAt, offset + line.length ])
        openedAt = null
      }
    }
    offset += line.length + 1
  }
  if (openedAt !== null) {
    ranges.push([ openedAt, text.length ])
  }
  return ranges
}
