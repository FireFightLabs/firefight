import { IconChevronDown, IconChevronRight, IconGitPullRequest } from "@tabler/icons-react"
import { useState } from "react"

import { Badge } from "@/components/ui/badge"
import { formatDate } from "@/lib/formatters"
import { newTabAttributes } from "@/lib/links"
import { PreventedEvidence } from "@/pages/halon/components/prevented-evidence"
import type { HalonPreventedProblem } from "@/types/serializers"

const SHORT_SHA = 7

// Where in the code it was, and the commit that fixed it, such as "app/models/order.rb:42, fixed in 1cb47a9".
function placeAndFix(problem: HalonPreventedProblem): string {
  const place = problem.path && (problem.line ? `${problem.path}:${problem.line}` : problem.path)
  const fix = problem.fixedInSha && `fixed in ${problem.fixedInSha.slice(0, SHORT_SHA)}`
  return [ place, fix ].filter(Boolean).join(", ")
}

// A problem a review caught and the author fixed before merging: the claim first, how it would have failed and the
// evidence behind a toggle, and the comment on the pull request one click away.
export function PreventedProblem({ problem }: { problem: HalonPreventedProblem }) {
  const [ expanded, setExpanded ] = useState(false)
  const pullRequest = `${problem.repository} #${problem.number}`
  const whereFixed = placeAndFix(problem)
  const Chevron = expanded ? IconChevronDown : IconChevronRight

  function toggle() {
    setExpanded(!expanded)
  }

  return (
    <li className="flex flex-col gap-2 border-b border-border px-5 py-4 last:border-b-0">
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <span className="flex min-w-0 items-baseline gap-1.5 text-sm">
          <IconGitPullRequest className="size-3.5 shrink-0 self-center text-fg-secondary" />
          {problem.pullRequestUrl ? (
            <a href={problem.pullRequestUrl} {...newTabAttributes(problem.pullRequestUrl)} className="font-medium whitespace-nowrap text-fg-primary hover:underline">
              {pullRequest}
            </a>
          ) : (
            <span className="font-medium whitespace-nowrap text-fg-primary">{pullRequest}</span>
          )}
          {problem.pullRequestTitle && <span className="truncate text-fg-secondary">{problem.pullRequestTitle}</span>}
        </span>
        <span className="text-xs text-fg-secondary">Merged {formatDate(problem.mergedAt)}</span>
      </div>

      <div className="flex flex-wrap gap-1.5">
        <Badge variant="outline">{problem.category}</Badge>
        <Badge variant="outline">{problem.severity}</Badge>
        {problem.serious && <Badge variant="secondary">Serious</Badge>}
      </div>

      <p className="text-sm font-medium text-fg-primary">{problem.claim}</p>

      <div className="flex flex-wrap items-center gap-x-4 gap-y-1">
        <button
          type="button"
          onClick={toggle}
          aria-expanded={expanded}
          className="inline-flex w-fit items-center gap-1.5 text-xs text-fg-secondary transition-colors hover:text-fg-primary"
        >
          <Chevron className="size-3.5" />
          {expanded ? "Hide how it would have failed" : "Show how it would have failed"}
        </button>
        {problem.commentUrl && (
          <a href={problem.commentUrl} {...newTabAttributes(problem.commentUrl)} className="text-xs text-fg-secondary hover:text-fg-primary hover:underline">
            Open the comment on the pull request
          </a>
        )}
      </div>

      {expanded && (
        <div className="flex flex-col gap-3 border-t border-border pt-3">
          <p className="text-sm text-fg-body">{problem.why}</p>
          {problem.failureChain.length > 0 && (
            <div className="flex flex-col gap-1">
              <h3 className="text-xs font-medium text-fg-secondary">How it would have failed</h3>
              <ol className="flex list-decimal flex-col gap-1 pl-5 text-sm text-fg-body">
                {problem.failureChain.map((step, index) => (
                  <li key={`${index}-${step}`}>{step}</li>
                ))}
              </ol>
            </div>
          )}
          {problem.evidence.length > 0 && (
            <div className="flex flex-col gap-1">
              <h3 className="text-xs font-medium text-fg-secondary">Evidence</h3>
              <ul className="flex flex-col gap-1">
                {problem.evidence.map((evidence, index) => (
                  <PreventedEvidence key={`${index}-${evidence.title}`} evidence={evidence} />
                ))}
              </ul>
            </div>
          )}
          {whereFixed && <p className="font-mono text-xs text-fg-secondary">{whereFixed}</p>}
        </div>
      )}
    </li>
  )
}
