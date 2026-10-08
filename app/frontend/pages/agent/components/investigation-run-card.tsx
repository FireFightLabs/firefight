import { Link, usePage } from "@inertiajs/react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { IncidentsBlocked, useIncidentsBlockedReason } from "@/components/incidents/incidents-blocked"
import ThinkingState, { type ThinkingRow, type ThinkingRowStatus } from "@/components/agent-ui/thinking-state"
import { MetricChart } from "@/components/charts/metric-chart"
import { formatSeconds } from "@/components/investigations/format"
import { isLive } from "@/components/investigations/use-live-investigation"
import { STEP_OUTCOME_KINDS } from "@/lib/generated/constants"
import { isOutcomeKind, type StepOutcomeKind } from "@/lib/step-outcome"
import { incidentPath } from "@/lib/routes"
import { AnswerText } from "@/pages/agent/components/answer-text"
import { LifecycleFormDialog } from "@/pages/incidents/components/index/lifecycle-form-dialog"
import { openRun, stopRun } from "@/pages/agent/lib/chat-updates"
import type { AgentPageProps } from "@/pages/agent/types"
import type { InvestigationCard } from "@/types/serializers"

interface InvestigationRunCardProps {
  toolCallKey: string
}

// The run a chat started, found by the tool call that started it. It is drawn like the chat's own lookups, with its steps
// as they happen and then the answer and any charts. The whole story opens over the chat, and an incident is offered
// when the answer says one is due.
export function InvestigationRunCard({ toolCallKey }: InvestigationRunCardProps) {
  const { investigations, conversation } = usePage<AgentPageProps>().props
  const [ declaring, setDeclaring ] = useState(false)
  const declareBlockedReason = useIncidentsBlockedReason()
  const run = investigations.find((candidate) => candidate.toolCallId === toolCallKey)
  if (!run || !conversation) {
    return null
  }

  const chatId = conversation.id
  const runId = run.id
  const working = isLive(run.status)

  function open() {
    openRun(chatId, runId)
  }

  function stop() {
    stopRun(runId)
  }

  function startDeclaring() {
    setDeclaring(true)
  }

  return (
    <section className="flex w-full flex-col gap-3" aria-label="Investigation">
      {run.question && <h3 className="truncate text-[13.5px] font-semibold text-ink">{run.question}</h3>}
      <ThinkingState
        rows={run.steps.map(toRow)}
        active="Investigating"
        done={doneLabel(run)}
        working={working}
      />
      {run.answer && <AnswerText text={run.answer} />}
      {run.charts.length > 0 && (
        <div className={`grid w-full gap-2 ${run.charts.length > 1 ? "max-w-160 sm:grid-cols-2" : "max-w-110"}`}>
          {run.charts.map((chart) => (
            <div key={chart.id} className="rounded-card bg-surface px-3.5 py-3 shadow-card">
              <MetricChart chart={chart} />
            </div>
          ))}
        </div>
      )}
      <div className="flex flex-wrap items-center gap-2">
        <Button size="sm" variant="secondary" onClick={open}>
          {working ? "Open the run" : "See how it got there"}
        </Button>
        {run.stopBlockedReason == null && (
          <Button size="sm" variant="secondary" onClick={stop}>
            Stop
          </Button>
        )}
        {run.suggestsIncident && (
          <IncidentsBlocked reason={declareBlockedReason}>
            <Button size="sm" variant="primary" onClick={startDeclaring} disabled={Boolean(declareBlockedReason)}>
              Declare incident
            </Button>
          </IncidentsBlocked>
        )}
        {run.incidentId && (
          <Link href={incidentPath(run.incidentId)} className="text-[12.5px] text-ink-2 hover:text-ink transition-colors duration-150">
            On {run.incidentIdentifier}
          </Link>
        )}
      </div>
      <LifecycleFormDialog incidentId={null} form="declare" open={declaring} onOpenChange={setDeclaring} fromInvestigationId={runId} suggestedName={run.question} />
    </section>
  )
}

function doneLabel(run: InvestigationCard) {
  const checked = run.steps.length === 1 ? "1 step" : `${run.steps.length} steps`
  return `Investigated in ${formatSeconds(run.durationSeconds)}, ${checked}`
}

type RunStep = InvestigationCard["steps"][number]

// The same marks as the run's story. A failure is red, and a not found answered its check so it is drawn quietly. A step
// still going keeps the trace's own mark, the last one spinning while the run works.
const OUTCOME_ROWS: Record<StepOutcomeKind, ThinkingRowStatus> = {
  [STEP_OUTCOME_KINDS.ANSWERED]: "done",
  [STEP_OUTCOME_KINDS.FAILED]: "failed",
  [STEP_OUTCOME_KINDS.NOT_FOUND]: "not_found",
  [STEP_OUTCOME_KINDS.REFUSED]: "refused",
}

function toRow(step: RunStep): ThinkingRow {
  return {
    id: String(step.position),
    primary: step.label,
    status: step.outcome && isOutcomeKind(step.outcome) ? OUTCOME_ROWS[step.outcome] : undefined,
  }
}
