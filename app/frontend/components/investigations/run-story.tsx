import {
  IconAlertTriangle,
  IconBulb,
  IconCircleCheck,
  IconCircleX,
  IconFlag,
  IconLoader2,
  IconMessageQuestion,
  IconMessagePlus,
  type Icon,
} from "@tabler/icons-react"
import type { ReactNode } from "react"

import { formatTime } from "@/lib/formatters"
import { HYPOTHESIS_STATUS, INVESTIGATION_STEP_STATUS } from "@/lib/generated/constants"
import { MetricChart } from "@/components/charts/metric-chart"
import { formatSeconds } from "@/components/investigations/format"
import { SETTLED_LABELS, STEP_LABELS, isKeyOf, labelFor } from "@/components/investigations/labels"
import { AddNote } from "@/components/investigations/add-note"
import { StopRun } from "@/components/investigations/stop-run"
import { StepDetails } from "@/components/investigations/step-row"
import { StepLinks } from "@/components/investigations/step-links"
import { type StoryEntry, buildStory } from "@/components/investigations/story"
import { HYPOTHESIS_TONES, STEP_TONES, TONE_CLASSES, type Tone } from "@/components/investigations/tone"
import { isLive } from "@/components/investigations/use-live-investigation"
import type { InvestigationDetail, InvestigationHypothesis } from "@/types/serializers"

interface RowProps {
  id?: string
  marker: ReactNode
  tone: Tone
  title: ReactNode
  at?: string | null
  aside?: ReactNode
  connected: boolean
  children?: ReactNode
}

function Row({ id, marker, tone, title, at, aside, connected, children }: RowProps) {
  return (
    <li id={id} className="relative scroll-mt-6 pb-5 target:[&_.story-card]:border-primary/60">
      {connected && <div aria-hidden className="absolute top-7 bottom-0 left-[14px] w-px bg-border" />}
      <div className="flex items-center gap-4">
        <div className={`relative z-10 flex size-[28px] shrink-0 items-center justify-center rounded-full border ${TONE_CLASSES[tone]}`}>
          {marker}
        </div>
        <div className="flex min-w-0 flex-1 flex-wrap items-center gap-x-2 text-sm">{title}</div>
        <span className="flex shrink-0 items-center gap-2 text-xs tabular-nums text-muted-foreground/80">
          {aside}
          {at && <span>{formatTime(at)}</span>}
        </span>
      </div>
      {children && <div className="story-card mt-2.5 ml-[44px] rounded-lg border border-border bg-card px-3.5 py-2.5 transition-colors">{children}</div>}
    </li>
  )
}

function IconMarker({ icon: Marker }: { icon: Icon }) {
  return <Marker className="size-[13px]" strokeWidth={1.75} />
}

function hypothesisTone(hypothesis: InvestigationHypothesis): Tone {
  return isKeyOf(HYPOTHESIS_TONES, hypothesis.status) ? HYPOTHESIS_TONES[hypothesis.status] : "neutral"
}

function EntryRow({ entry, investigation, connected }: { entry: StoryEntry; investigation: InvestigationDetail; connected: boolean }) {
  switch (entry.kind) {
    case "asked": {
      const who = investigation.asker?.name ?? "Someone"
      return (
        <Row
          marker={<IconMarker icon={IconMessageQuestion} />}
          tone="primary"
          title={
            <>
              <span className="font-medium">{who}</span>
              <span className="text-muted-foreground">{investigation.question ? "asked" : "asked for an investigation"}</span>
            </>
          }
          at={investigation.createdAt}
          connected={connected}
        >
          {investigation.question && <p className="text-sm leading-relaxed">{investigation.question}</p>}
        </Row>
      )
    }
    case "step": {
      const { step } = entry
      const tone = isKeyOf(STEP_TONES, step.status) ? STEP_TONES[step.status] : "neutral"
      const stepCharts = investigation.charts.filter((chart) => chart.stepPosition === step.position)
      return (
        <Row
          id={`step-${step.position}`}
          marker={step.status === INVESTIGATION_STEP_STATUS.RUNNING ? <IconLoader2 className="size-3.5 animate-spin" /> : <span className="font-mono text-[11px] tabular-nums">{step.position}</span>}
          tone={tone}
          title={<span className="font-medium text-foreground/95">{step.label}</span>}
          aside={
            <>
              {step.status === INVESTIGATION_STEP_STATUS.FAILED && <span className="text-rose-600 dark:text-rose-400">{labelFor(STEP_LABELS, step.status)}</span>}
              {step.seconds != null && <span>{formatSeconds(step.seconds)}</span>}
            </>
          }
          at={step.startedAt}
          connected={connected}
        >
          <StepDetails step={step} />
          {stepCharts.map((chart) => (
            <div key={chart.id} className="mt-3 rounded-lg border border-border bg-card px-3 py-2.5">
              <MetricChart chart={chart} />
            </div>
          ))}
        </Row>
      )
    }
    case "theory":
      return (
        <Row
          marker={<IconMarker icon={IconBulb} />}
          tone="violet"
          title={<span className="text-muted-foreground">New theory</span>}
          at={entry.hypothesis.createdAt}
          connected={connected}
        >
          <p className="text-sm leading-relaxed">{entry.hypothesis.assertion}</p>
        </Row>
      )
    case "settled": {
      const { hypothesis } = entry
      const confirmed = hypothesis.status === HYPOTHESIS_STATUS.SUPPORTED
      return (
        <Row
          marker={<IconMarker icon={confirmed ? IconCircleCheck : IconCircleX} />}
          tone={hypothesisTone(hypothesis)}
          title={<span className="font-medium">{labelFor(SETTLED_LABELS, hypothesis.status)}</span>}
          connected={connected}
        >
          <div className="flex flex-col gap-1.5">
            <p className={`text-sm leading-relaxed ${confirmed ? "" : "text-muted-foreground"}`}>{hypothesis.assertion}</p>
            <StepLinks steps={hypothesis.steps} />
          </div>
        </Row>
      )
    }
    case "note": {
      const { note } = entry
      return (
        <Row
          marker={<IconMarker icon={IconMessagePlus} />}
          tone="primary"
          title={
            <>
              <span className="font-medium">{note.author?.name ?? "A responder"}</span>
              <span className="text-muted-foreground">{note.takenAt ? "added" : "added, waiting for the next step"}</span>
            </>
          }
          at={note.createdAt}
          connected={connected}
        >
          <p className="text-sm leading-relaxed">{note.content}</p>
        </Row>
      )
    }
    case "end":
      return <EndRow investigation={investigation} />
  }
}

function EndRow({ investigation }: { investigation: InvestigationDetail }) {
  if (isLive(investigation.status)) {
    return (
      <>
        <Row
          marker={<IconLoader2 className="size-3.5 animate-spin" />}
          tone="primary"
          title={<span className="text-muted-foreground">Still working. This updates as it goes.</span>}
          aside={investigation.stopBlockedReason == null && <StopRun investigationId={investigation.id} />}
          connected={false}
        />
        {investigation.noteBlockedReason == null && (
          <li>
            <AddNote investigationId={investigation.id} />
          </li>
        )}
      </>
    )
  }
  if (investigation.finding) {
    return (
      <Row
        marker={<IconMarker icon={IconFlag} />}
        tone="emerald"
        title={<span className="font-medium">Answered</span>}
        at={investigation.completedAt}
        connected={false}
      />
    )
  }
  return (
    <Row
      marker={<IconMarker icon={IconAlertTriangle} />}
      tone="amber"
      title={<span className="font-medium">Stopped</span>}
      at={investigation.completedAt}
      connected={false}
    >
      <p className="text-sm text-muted-foreground">{investigation.stoppedBecause ?? "Stopped without an answer."}</p>
    </Row>
  )
}

// What it was asked, every step it took, the theories as it formed and settled them, and how it ended.
export function RunStory({ investigation }: { investigation: InvestigationDetail }) {
  const story = buildStory(investigation)

  return (
    <ol className="relative">
      {story.map((entry, index) => (
        <EntryRow key={entry.key} entry={entry} investigation={investigation} connected={index < story.length - 1} />
      ))}
    </ol>
  )
}
