import { WaitingLine } from "@/components/code-fix/waiting-line"
import { activityShare, activityWords } from "@/pages/agent/lib/tool-activity"
import type { ToolActivity } from "@/pages/agent/types"

// What a long tool says about how far it got, under its step while it runs, such as helpers reporting one by one or a
// browser taking the steps of a path. A count it gives is drawn as a thin bar under the words.
export function StepActivity({ activity }: { activity: ToolActivity }) {
  const words = activityWords(activity)
  const share = activityShare(activity)
  const width = share === null ? null : `${Math.round(share * 100)}%`

  return (
    <div className="flex min-w-0 flex-col gap-1.5 text-[12px] leading-5" aria-live="polite">
      <WaitingLine words={words} />
      {width && (
        <span
          role="progressbar"
          aria-label={words}
          aria-valuemin={0}
          aria-valuemax={activity.total ?? undefined}
          aria-valuenow={activity.value ?? undefined}
          className="relative ml-[17px] h-[3px] w-40 max-w-full overflow-hidden rounded-full bg-line"
        >
          <span className="absolute inset-y-0 left-0 rounded-full bg-accent transition-[width] duration-300" style={{ width }} />
        </span>
      )}
    </div>
  )
}
