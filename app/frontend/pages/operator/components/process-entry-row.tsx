import { Link } from "@inertiajs/react"
import {
  IconBell,
  IconChevronRight,
  IconFlame,
  IconHierarchy2,
  IconPlugConnectedX,
  IconSparkles,
  IconStepInto,
  IconWebhook,
  type Icon,
} from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import { formatDateTime, formatTime } from "@/lib/formatters"
import { OPERATOR_PROCESS_KINDS, OPERATOR_PROCESS_TONES } from "@/pages/operator/generated/constants"
import { operatorHalonRunPath } from "@/lib/routes"
import { RedeliverButton } from "@/pages/operator/components/redeliver-button"
import { StepActions } from "@/pages/operator/components/step-actions"
import { processToneClasses } from "@/pages/operator/lib/tone"
import type { OperatorProcessEntry } from "@/types/serializers"

const KINDS: Record<OperatorProcessEntry["kind"], { label: string; icon: Icon }> = {
  [OPERATOR_PROCESS_KINDS.ALERT]: { label: "Alert", icon: IconBell },
  [OPERATOR_PROCESS_KINDS.INCIDENT]: { label: "Incident", icon: IconFlame },
  [OPERATOR_PROCESS_KINDS.WORKFLOW]: { label: "Workflow", icon: IconHierarchy2 },
  [OPERATOR_PROCESS_KINDS.STEP]: { label: "Step", icon: IconStepInto },
  [OPERATOR_PROCESS_KINDS.WEBHOOK]: { label: "Webhook", icon: IconWebhook },
  [OPERATOR_PROCESS_KINDS.PLATFORM]: { label: "Platform call", icon: IconPlugConnectedX },
  [OPERATOR_PROCESS_KINDS.HALON]: { label: "Halon", icon: IconSparkles },
}

export function ProcessEntryRow({ entry, last }: { entry: OperatorProcessEntry; last: boolean }) {
  const [open, setOpen] = useState(false)
  const kind = KINDS[entry.kind]
  const KindIcon = kind.icon
  const failed = entry.tone === OPERATOR_PROCESS_TONES.BAD

  function toggle() {
    setOpen(!open)
  }

  return (
    <li className="relative grid grid-cols-[30px_minmax(0,1fr)_auto] gap-4 pb-5">
      {!last && <span aria-hidden className="absolute top-8 bottom-0 left-[14.5px] w-px bg-border" />}
      <span className={`relative z-10 flex size-[30px] items-center justify-center rounded-full border ${processToneClasses(entry.tone)}`}>
        <KindIcon className="size-3.5" stroke={1.7} />
      </span>
      <div className="flex min-w-0 flex-col gap-1 pt-1">
        <div className="flex items-baseline gap-3">
          <span className={`text-sm font-medium ${entry.kind === OPERATOR_PROCESS_KINDS.STEP ? "font-mono text-[13px]" : ""} ${failed ? "text-error" : ""}`}>{entry.title}</span>
          <span className="text-fg-muted text-xs">{kind.label}</span>
        </div>
        {entry.detail && <p className="text-muted-foreground text-[13px]">{entry.detail}</p>}
        {entry.technical && (
          <>
            <button type="button" onClick={toggle} aria-expanded={open} className="text-muted-foreground hover:text-foreground inline-flex w-fit items-center gap-1 text-xs">
              <IconChevronRight className={`size-3.5 transition-transform ${open ? "rotate-90" : ""}`} />
              {open ? "Hide the error" : "Show the error"}
            </button>
            {open && (
              <pre className="bg-muted/40 max-h-72 overflow-auto rounded-md border border-border p-3 font-mono text-xs whitespace-pre-wrap text-error">{entry.technical}</pre>
            )}
          </>
        )}
      </div>
      <div className="flex items-start gap-3 pt-0.5">
        {entry.retryStepId && <StepActions stepId={entry.retryStepId} stepName={entry.title} />}
        {entry.redeliverId && <RedeliverButton deliveryId={entry.redeliverId} />}
        {entry.runId && (
          <Button asChild size="sm" variant="outline">
            <Link href={operatorHalonRunPath(entry.runId)}>Trace</Link>
          </Button>
        )}
        <time dateTime={entry.at} className="text-fg-muted pt-1.5 font-mono text-xs" title={formatDateTime(entry.at)}>
          {formatTime(entry.at)}
        </time>
      </div>
    </li>
  )
}
