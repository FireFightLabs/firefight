import { Link, usePage } from "@inertiajs/react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import ThinkingState from "@/components/agent-ui/thinking-state"
import { MetricChart } from "@/components/charts/metric-chart"
import { formatSeconds } from "@/components/investigations/format"
import { isLive } from "@/components/investigations/use-live-investigation"
import { incidentPath } from "@/lib/routes"
import { AnswerText } from "@/pages/agent/components/answer-text"
import { LifecycleFormDialog } from "@/pages/incidents/components/index/lifecycle-form-dialog"
import { openRun } from "@/pages/agent/lib/chat-updates"
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

  function startDeclaring() {
    setDeclaring(true)
  }

  return (
    <section className="flex w-full flex-col gap-3" aria-label="Investigation">
      {run.question && <h3 className="truncate text-[13.5px] font-semibold text-ink">{run.question}</h3>}
      <ThinkingState
        rows={run.steps.map((step) => ({ id: String(step.position), primary: step.label }))}
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
        {run.suggestsIncident && (
          <Button size="sm" variant="primary" onClick={startDeclaring}>
            Declare incident
          </Button>
        )}
        {run.incidentId && (
          <Link href={incidentPath(run.incidentId)} className="text-[12.5px] text-ink-2 hover:text-ink">
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
