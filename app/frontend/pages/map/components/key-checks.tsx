import { useEffect, useState } from "react"
import { IconExternalLink, IconLoader2, IconPlayerPlay } from "@tabler/icons-react"

import { MetricChart } from "@/components/charts/metric-chart"
import { Button } from "@/components/ui/button"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { postJson, requestJson } from "@/lib/http"
import { resourceMapResourceCheckPath, resourceMapResourceChecksPath } from "@/lib/routes"
import type { ResourceMapCheck, ResourceMapCheckOutcome } from "@/types/serializers"

interface ChecksAnswer {
  checks: ResourceMapCheck[]
  none: string | null
}

type Loaded = { state: "loading" } | { state: "failed" } | { state: "loaded"; answer: ChecksAnswer }

// The checks worth running first on a resource, read when its panel opens, since whether each can run is worked out
// live from the connections that run or watch it.
export function KeyChecks({ resourceId }: { resourceId: string }) {
  const [ loaded, setLoaded ] = useState<Loaded>({ state: "loading" })

  useEffect(() => {
    const controller = new AbortController()
    setLoaded({ state: "loading" })
    requestJson<ChecksAnswer>(resourceMapResourceChecksPath(resourceId), { method: "GET", signal: controller.signal })
      .then(({ ok, data }) => {
        setLoaded(ok && data ? { state: "loaded", answer: data } : { state: "failed" })
      })
      .catch(() => {
        if (!controller.signal.aborted) {
          setLoaded({ state: "failed" })
        }
      })
    return () => {
      controller.abort()
    }
  }, [ resourceId ])

  if (loaded.state === "loading") {
    return <p className="text-sm text-muted-foreground">Working out which checks can run here.</p>
  }
  if (loaded.state === "failed") {
    return <p className="text-sm text-muted-foreground">The checks could not be read. Open the resource again to retry.</p>
  }
  if (loaded.answer.none) {
    return <p className="text-sm text-muted-foreground">{loaded.answer.none}</p>
  }

  return (
    <div className="flex flex-col gap-2">
      {loaded.answer.checks.map((check) => (
        <CheckRow key={check.key} resourceId={resourceId} check={check} />
      ))}
    </div>
  )
}

type Run = { state: "idle" } | { state: "running" } | { state: "done"; outcome: ResourceMapCheckOutcome } | { state: "failed" }

function CheckRow({ resourceId, check }: { resourceId: string; check: ResourceMapCheck }) {
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
        {check.available && <RunButton reason={check.runBlockedReason} running={run.state === "running"} again={run.state !== "idle"} onRun={start} />}
      </div>
      {!check.available && check.runBlockedReason && <p className="text-xs text-muted-foreground">{check.runBlockedReason}</p>}
      {run.state === "failed" && <p className="text-xs text-destructive">The check did not answer. Try running it again.</p>}
      {run.state === "done" && <Outcome outcome={run.outcome} />}
    </div>
  )
}

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

interface RunButtonProps {
  reason?: string
  running: boolean
  again: boolean
  onRun: () => void
}

// Someone who may not run it still sees the button, with the grant it needs in its tooltip.
function RunButton({ reason, running, again, onRun }: RunButtonProps) {
  const button = (
    <Button type="button" size="sm" variant="outline" className="shrink-0" disabled={Boolean(reason) || running} onClick={onRun}>
      {running ? <IconLoader2 className="motion-safe:animate-spin" /> : <IconPlayerPlay />}
      {again ? "Run again" : "Run"}
    </Button>
  )
  if (!reason) {
    return button
  }

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span className="shrink-0">{button}</span>
      </TooltipTrigger>
      <TooltipContent className="max-w-xs">{reason}</TooltipContent>
    </Tooltip>
  )
}

function Outcome({ outcome }: { outcome: ResourceMapCheckOutcome }) {
  if (outcome.refusal) {
    return <p className={`text-xs ${outcome.approvalId ? "text-muted-foreground" : "text-destructive"}`}>{outcome.refusal}</p>
  }

  return (
    <div className="flex flex-col gap-2 border-t border-border/60 pt-2">
      {outcome.headline && <p className={`text-sm leading-relaxed ${outcome.failed ? "text-destructive" : ""}`}>{outcome.headline}</p>}
      {outcome.charts.map((chart) => (
        <MetricChart key={chart.id} chart={chart} />
      ))}
      {outcome.text && (
        <pre className="max-h-48 overflow-auto rounded-md bg-muted/40 px-2.5 py-2 font-mono text-[11.5px] leading-relaxed whitespace-pre-wrap">{outcome.text}</pre>
      )}
      {outcome.link && (
        <a href={outcome.link} target="_blank" rel="noreferrer" className="flex w-fit items-center gap-1.5 text-xs text-link hover:underline">
          Open this at its source
          <IconExternalLink className="size-3" />
        </a>
      )}
    </div>
  )
}
