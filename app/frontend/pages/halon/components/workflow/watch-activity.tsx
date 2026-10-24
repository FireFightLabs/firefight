import { WatchedThing } from "@/pages/halon/components/workflow/watched-thing"
import { clockLabel, untilLabel } from "@/pages/halon/lib/workflow/run-states"
import type { WorkflowRunStep } from "@/types/serializers"

type Watching = NonNullable<WorkflowRunStep["watch"]>

interface WatchActivityProps {
  watch: Watching
  // The time now, ticking while the watch goes, for when it reads next.
  now: number
}

// Where the watch a Watch step keeps stands: each thing it follows with where it stands and the page of its run, what it
// last saw of it and when, how often it read, when it reads next and when it gives up.
export function WatchActivity({ watch, now }: WatchActivityProps) {
  return (
    <section className="space-y-2 rounded-sm border border-border p-2.5" aria-label="The watch">
      <div className="space-y-0.5">
        <h5 className="text-xs font-medium text-fg-primary [overflow-wrap:anywhere]">{watch.headline}</h5>
        <p className="text-[11.5px] text-fg-muted">{watch.reads}</p>
        {watch.active ? (
          <p className="text-[11.5px] text-fg-muted">
            {watch.checkedAt ? `Last read at ${clockLabel(watch.checkedAt)}. ` : "Not read yet. "}
            {watch.nextCheckAt && `Reads next ${untilLabel(watch.nextCheckAt, now)}. `}
            Gives up at {clockLabel(watch.expiresAt)}.
          </p>
        ) : (
          watch.checkedAt && <p className="text-[11.5px] text-fg-muted">Last read at {clockLabel(watch.checkedAt)}.</p>
        )}
      </div>
      <ul className="space-y-2">
        {watch.steps.map((watched) => (
          <WatchedThing key={watched.id} watched={watched} />
        ))}
      </ul>
    </section>
  )
}
