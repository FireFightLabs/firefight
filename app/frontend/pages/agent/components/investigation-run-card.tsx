import { Link, usePage } from "@inertiajs/react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { InvestigationStatusBadge } from "@/components/investigations/status-badge"
import { incidentPath } from "@/lib/routes"
import { LifecycleFormDialog } from "@/pages/incidents/components/index/lifecycle-form-dialog"
import { openRun } from "@/pages/agent/lib/chat-updates"
import type { AgentPageProps } from "@/pages/agent/types"

interface InvestigationRunCardProps {
  toolCallKey: string
}

// The run a chat started, found by the tool call that started it. It says how the run is going and ends with its answer,
// opens the whole story over the chat, and offers to declare an incident when the answer says one is due.
export function InvestigationRunCard({ toolCallKey }: InvestigationRunCardProps) {
  const { investigations, conversation } = usePage<AgentPageProps>().props
  const [ declaring, setDeclaring ] = useState(false)
  const run = investigations.find((candidate) => candidate.toolCallId === toolCallKey)
  if (!run || !conversation) {
    return null
  }

  const chatId = conversation.id
  const runId = run.id

  function open() {
    openRun(chatId, runId)
  }

  function startDeclaring() {
    setDeclaring(true)
  }

  return (
    <section className="flex w-full max-w-110 flex-col gap-3 rounded-card bg-surface px-3.5 py-3 shadow-card" aria-label="Investigation">
      <header className="flex items-center justify-between gap-3">
        <h3 className="truncate text-[13.5px] font-semibold text-ink">{run.question ?? `Investigating ${run.incidentIdentifier ?? ""}`}</h3>
        <InvestigationStatusBadge status={run.status} />
      </header>
      {run.answer && <p className="line-clamp-4 text-[13px] leading-relaxed text-ink-2">{run.answer}</p>}
      <div className="flex flex-wrap items-center gap-2">
        <Button size="sm" variant="secondary" onClick={open}>
          Open
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
