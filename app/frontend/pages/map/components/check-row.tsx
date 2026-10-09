import { useState } from "react"
import { IconLoader2, IconPlayerPlay } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import { postJson } from "@/lib/http"
import { resourceMapResourceCheckPath } from "@/lib/routes"
import { CheckOutcome } from "@/pages/map/components/check-outcome"
import type { ResourceMapCheck, ResourceMapCheckOutcome } from "@/types/serializers"

type Run = { state: "idle" } | { state: "running" } | { state: "done"; outcome: ResourceMapCheckOutcome } | { state: "failed" }

function subtitle(check: ResourceMapCheck): string {
  if (!check.available) {
    return "Not available here"
  }
  const read = check.reads ? `Read as ${check.reads} from ${check.connection}` : `From ${check.connection}`
  if (!check.readsMetric) {
    return read
  }
  return check.normal ? `${read}. Normal: ${check.normal}` : `${read}. No normal read yet`
}

// Someone who may not run a check still sees its button, with the grant it needs in its tooltip.
export function CheckRow({ resourceId, check }: { resourceId: string; check: ResourceMapCheck }) {
  const [ run, setRun ] = useState<Run>({ state: "idle" })
  const approvalId = run.state === "done" ? run.outcome.approvalId : undefined

  async function start() {
    setRun({ state: "running" })
    try {
      const { data } = await postJson<{ outcome: ResourceMapCheckOutcome }>(resourceMapResourceCheckPath(resourceId, check.key), approvalId ? { approval_id: approvalId } : undefined)
      setRun(data?.outcome ? { state: "done", outcome: data.outcome } : { state: "failed" })
    } catch {
      setRun({ state: "failed" })
    }
  }

  return (
    <div className={`flex flex-col gap-2 rounded-lg border px-3 py-2.5 ${check.available ? "border-border bg-background/50" : "border-dashed border-border"}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 flex-col gap-0.5">
          <span className={`text-sm font-semibold ${check.available ? "" : "text-muted-foreground"}`}>{check.label}</span>
          <span className="text-xs text-muted-foreground">{subtitle(check)}</span>
        </div>
        {check.available && (
          <Blocked reason={check.runBlockedReason}>
            <Button type="button" size="sm" variant="outline" className="shrink-0" disabled={Boolean(check.runBlockedReason) || run.state === "running"} onClick={start}>
              {run.state === "running" ? <IconLoader2 className="motion-safe:animate-spin" /> : <IconPlayerPlay />}
              {run.state === "idle" ? "Run" : "Run again"}
            </Button>
          </Blocked>
        )}
      </div>
      {!check.available && check.runBlockedReason && <p className="text-xs text-muted-foreground">{check.runBlockedReason}</p>}
      {run.state === "failed" && <p className="text-xs text-destructive">The check did not answer. Try running it again.</p>}
      {run.state === "done" && <CheckOutcome outcome={run.outcome} />}
    </div>
  )
}
