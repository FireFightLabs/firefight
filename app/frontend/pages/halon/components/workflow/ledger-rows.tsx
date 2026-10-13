import { formatTime } from "@/lib/formatters"
import { LEDGER_DECISION } from "@/lib/generated/constants"
import type { WorkflowRunStep } from "@/types/serializers"

type Call = WorkflowRunStep["invocations"][number]

const DECISION_WORDS: Record<Call["decision"], string> = { allow: "Allowed", deny: "Refused", pending: "Held for approval" }
const DECISION_TONES: Record<Call["decision"], string> = { allow: "text-success", deny: "text-error", pending: "text-warning" }

// Every call a step made through the gateway, as the activity log keeps it: what it called, whether it was allowed,
// held or refused, how it ended and when.
export function LedgerRows({ calls }: { calls: Call[] }) {
  if (calls.length === 0) {
    return <p className="text-xs text-fg-muted">It called nothing through the gateway.</p>
  }

  return (
    <ul className="divide-y divide-border rounded-sm border border-border">
      {calls.map((call) => (
        <li key={call.id} className="space-y-0.5 px-2.5 py-2 text-xs">
          <div className="flex items-baseline justify-between gap-2">
            <code className="truncate font-mono text-fg-primary">{call.actionKey}</code>
            <span className="shrink-0 text-[11px] text-fg-muted">{formatTime(call.createdAt)}</span>
          </div>
          <p className={DECISION_TONES[call.decision]}>
            {DECISION_WORDS[call.decision]}
            {call.approvalStatus && call.decision === LEDGER_DECISION.PENDING ? `, the approval is ${call.approvalStatus}` : ""}
            {call.outcome ? `, ended in ${call.outcome}` : ""}
            {call.durationMs !== null ? ` after ${call.durationMs} ms` : ""}
          </p>
          {call.errorSummary && <p className="text-fg-secondary">{call.errorSummary}</p>}
        </li>
      ))}
    </ul>
  )
}
