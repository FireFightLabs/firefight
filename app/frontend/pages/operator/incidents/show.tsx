import { Link, usePage } from "@inertiajs/react"
import {
  IconBell,
  IconChevronRight,
  IconFlame,
  IconHierarchy2,
  IconPlugConnectedX,
  IconRefresh,
  IconSparkles,
  IconStepInto,
  IconWebhook,
  type Icon,
} from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { formatDateTime, formatTime } from "@/lib/formatters"
import { OPERATOR_PROCESS_KINDS, OPERATOR_PROCESS_TONES } from "@/lib/generated/constants"
import { operatorHalonRunPath, operatorIncidentsPath, redeliverOperatorWebhookDeliveryPath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { StepActions } from "@/pages/operator/components/step-actions"
import { useAction } from "@/pages/operator/lib/use-action"
import { TONE_CLASSES, processToneClasses } from "@/pages/operator/lib/tone"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorIncidentRow, OperatorProcessEntry } from "@/types/serializers"

interface IncidentProps extends OperatorPageProps {
  incident: OperatorIncidentRow
  entries: OperatorProcessEntry[]
  total: number
}

const KINDS: Record<OperatorProcessEntry["kind"], { label: string; icon: Icon }> = {
  alert: { label: "Alert", icon: IconBell },
  incident: { label: "Incident", icon: IconFlame },
  workflow: { label: "Workflow", icon: IconHierarchy2 },
  step: { label: "Step", icon: IconStepInto },
  webhook: { label: "Webhook", icon: IconWebhook },
  platform: { label: "Platform call", icon: IconPlugConnectedX },
  halon: { label: "Halon", icon: IconSparkles },
}

function Redeliver({ deliveryId }: { deliveryId: string }) {
  const { busy, post } = useAction()

  function redeliver() {
    post(redeliverOperatorWebhookDeliveryPath(deliveryId))
  }

  return (
    <Button type="button" size="sm" variant="outline" onClick={redeliver} disabled={busy}>
      <IconRefresh className="size-3.5" />
      Send again
    </Button>
  )
}

function EntryRow({ entry, last }: { entry: OperatorProcessEntry; last: boolean }) {
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
          <span className={`text-sm font-medium ${entry.kind === OPERATOR_PROCESS_KINDS.STEP ? "font-mono text-[13px]" : ""} ${failed ? "text-rose-400" : ""}`}>{entry.title}</span>
          <span className="text-muted-foreground/70 text-xs">{kind.label}</span>
        </div>
        {entry.detail && <p className="text-muted-foreground text-[13px]">{entry.detail}</p>}
        {entry.technical && (
          <>
            <button type="button" onClick={toggle} aria-expanded={open} className="text-muted-foreground hover:text-foreground inline-flex w-fit items-center gap-1 text-xs">
              <IconChevronRight className={`size-3.5 transition-transform ${open ? "rotate-90" : ""}`} />
              {open ? "Hide the error" : "Show the error"}
            </button>
            {open && (
              <pre className="bg-muted/40 max-h-72 overflow-auto rounded-md border border-border p-3 font-mono text-xs whitespace-pre-wrap text-rose-300">{entry.technical}</pre>
            )}
          </>
        )}
      </div>
      <div className="flex items-start gap-3 pt-0.5">
        {entry.retryStepId && <StepActions stepId={entry.retryStepId} stepName={entry.title} />}
        {entry.redeliverId && <Redeliver deliveryId={entry.redeliverId} />}
        {entry.runId && (
          <Button asChild size="sm" variant="outline">
            <Link href={operatorHalonRunPath(entry.runId)}>Trace</Link>
          </Button>
        )}
        <time dateTime={entry.at} className="text-muted-foreground/80 pt-1.5 font-mono text-xs" title={formatDateTime(entry.at)}>
          {formatTime(entry.at)}
        </time>
      </div>
    </li>
  )
}

export default function OperatorIncident() {
  const { incident, entries, total } = usePage<IncidentProps>().props

  return (
    <OperatorLayout title={incident.identifier}>
      <Link href={operatorIncidentsPath()} className="text-muted-foreground hover:text-foreground mb-3 inline-block text-sm">
        All incidents
      </Link>
      <PageHeading
        title={
          <span className="flex items-baseline gap-3">
            <span className="font-mono">{incident.identifier}</span>
            <span>{incident.name}</span>
          </span>
        }
        lead="Everything Firefight did for this incident, in order: its alerts and routing, its events, each workflow step, webhook deliveries, failed calls to the chat platform, and Halon's runs."
      />
      <div className="mb-6 flex flex-wrap gap-2 text-xs">
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.primary}`}>{incident.status}</span>
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.neutral}`}>{incident.workspaceName}</span>
        {incident.problems > 0 && (
          <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.rose}`}>{incident.problems} failed</span>
        )}
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.neutral}`}>
          {entries.length < total ? `first ${entries.length} of ${total} records` : `${total} records`}
        </span>
      </div>
      <Card className="px-6 pt-6 pb-1">
        {entries.length === 0 ? (
          <p className="text-muted-foreground pb-5 text-sm">Nothing recorded for this incident yet.</p>
        ) : (
          <ol className="list-none">
            {entries.map((entry, index) => (
              <EntryRow key={entry.key} entry={entry} last={index === entries.length - 1} />
            ))}
          </ol>
        )}
      </Card>
    </OperatorLayout>
  )
}
