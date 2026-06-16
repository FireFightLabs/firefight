import { Link, router } from "@inertiajs/react"
import { IconArrowRight, IconFileText, IconSparkles } from "@tabler/icons-react"
import { toast } from "sonner"

import { Button } from "@/components/ui/button"
import { LIFECYCLE_STAGES, type LifecycleStageKey } from "@/lib/constants"
import {
  incidentPostmortemGeneratePath,
  incidentPostmortemPath,
  incidentPostmortemStartBlankPath,
} from "@/lib/routes"

const statusLabels: Record<string, string> = {
  draft: "Draft",
  in_progress: "In progress",
  in_review: "In review",
  completed: "Completed",
}

const statusDotColors: Record<string, string> = {
  draft: "bg-muted-foreground/50",
  in_progress: "bg-amber-400",
  in_review: "bg-sky-400",
  completed: "bg-emerald-400",
}

export function IncidentPostmortemCard({
  incidentId,
  hasPostmortem,
  postmortemStatus,
  incidentLifecycleStage,
}: {
  incidentId: string
  hasPostmortem: boolean
  postmortemStatus?: string
  incidentLifecycleStage: LifecycleStageKey
}) {
  const canCreate = incidentLifecycleStage === LIFECYCLE_STAGES.CLOSED
  if (hasPostmortem) {
    const status = postmortemStatus ?? "draft"
    return (
      <Link
        href={incidentPostmortemPath(incidentId)}
        className="group block rounded-xl border border-primary/25 bg-card px-4 py-4 transition-colors hover:border-primary/45 hover:bg-accent"
      >
        <div className="flex items-center gap-3">
          <div className="flex size-9 items-center justify-center rounded-lg bg-primary/10 ring-1 ring-primary/20">
            <IconFileText className="size-[17px] text-primary" strokeWidth={1.75} />
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5">
              <span className="text-[13px] font-semibold text-foreground">Postmortem</span>
            </div>
            <div className="mt-0.5 flex items-center gap-1.5 text-[11px] text-muted-foreground">
              <span
                className={`size-1.5 rounded-full ${statusDotColors[status]}`}
                aria-hidden
              />
              <span>{statusLabels[status]}</span>
              <span className="text-muted-foreground/40">·</span>
              <span className="truncate">Root cause & actions</span>
            </div>
          </div>
          <IconArrowRight className="size-4 text-muted-foreground/40 transition-all group-hover:translate-x-0.5 group-hover:text-primary" />
        </div>
      </Link>
    )
  }

  if (!canCreate) {
    return (
      <section className="flex items-center gap-2.5 rounded-xl border border-border bg-card px-4 py-3">
        <IconFileText className="size-4 shrink-0 text-muted-foreground/60" strokeWidth={1.75} />
        <span className="text-[12px] text-muted-foreground">
          Postmortem · Generate once resolved
        </span>
      </section>
    )
  }

  return (
    <section className="rounded-xl border border-border bg-card px-5 py-5">
      <div className="flex items-start gap-3">
        <div className="flex size-9 items-center justify-center rounded-lg bg-muted/70">
          <IconFileText className="size-[17px] text-muted-foreground/80" strokeWidth={1.75} />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-[13px] font-semibold text-foreground">No postmortem yet</p>
          <p className="mt-1 text-[12px] leading-[1.55] text-muted-foreground/90">
            Capture what happened, why it happened, and what prevents it next time.
          </p>
        </div>
      </div>
      <div className="mt-4 flex items-center gap-2">
        <Button
          size="sm"
          className="h-8 gap-1.5 px-3 text-[12px]"
          onClick={() => {
            router.post(incidentPostmortemGeneratePath(incidentId), {}, {
              preserveScroll: true,
              onSuccess: () => toast.success("Generating postmortem. This usually takes under a minute."),
              onError: () => toast.error("Failed to start generation."),
            })
          }}
        >
          <IconSparkles className="size-3.5" strokeWidth={2} />
          Generate draft
        </Button>
        <Button
          variant="ghost"
          size="sm"
          className="h-8 px-2.5 text-[12px] text-muted-foreground"
          onClick={() => router.post(incidentPostmortemStartBlankPath(incidentId))}
        >
          Start blank
        </Button>
      </div>
    </section>
  )
}
