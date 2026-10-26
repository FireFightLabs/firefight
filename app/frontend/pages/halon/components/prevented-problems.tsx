import { InfiniteScroll } from "@inertiajs/react"

import { Card } from "@/components/ui/card"
import { HALON_PERFORMANCE_PROPS } from "@/lib/generated/constants"
import { PreventedProblem } from "@/pages/halon/components/prevented-problem"
import { ShowMore } from "@/pages/halon/components/show-more"
import type { HalonPreventedProblem } from "@/types/serializers"

function caught(count: number): string {
  return `${count} risky change${count === 1 ? "" : "s"} caught`
}

// The problems Halon's pull request reviews prevented in the window, each one open to read: the pull request, what was
// caught, how it would have failed and the evidence for it.
export function PreventedProblems({ problems, count, days }: { problems: HalonPreventedProblem[]; count: number; days: number }) {
  return (
    <Card className="gap-0 overflow-hidden py-0">
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b border-border px-5 py-4">
        <div>
          <h2 className="text-sm font-semibold text-fg-primary">Problems prevented by pull request review</h2>
          <p className="mt-1 text-xs text-fg-secondary">
            Serious, major or critical findings that were fixed before their pull request merged, newest merge first.
          </p>
        </div>
        <span className="text-sm font-semibold text-fg-primary">
          {caught(count)} in the last {days} days
        </span>
      </div>
      {count === 0 ? (
        <p className="px-5 py-8 text-center text-sm text-fg-secondary">
          No pull request merged in the last {days} days with a serious or major finding fixed first.
        </p>
      ) : (
        // A window is a new list, so the pages loaded for the last one are forgotten with it.
        <InfiniteScroll key={days} data={HALON_PERFORMANCE_PROPS.PREVENTED} as="ul" manual preserveUrl onlyNext next={ShowMore}>
          {problems.map((problem) => (
            <PreventedProblem key={problem.id} problem={problem} />
          ))}
        </InfiniteScroll>
      )}
    </Card>
  )
}
