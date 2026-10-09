import { IconAlertTriangle, IconCheck } from "@tabler/icons-react"

import { Notes } from "@/components/code-fix/notes"
import type { CodeFixReview } from "@/lib/code-fix-work"

// What Halon's review made of the change before it opened, and what nobody could verify, which a reviewer checks first.
export function Review({ review }: { review: CodeFixReview }) {
  if (!review.ran) {
    return (
      <span className="flex items-start gap-1.5 font-medium text-warning">
        <IconAlertTriangle aria-hidden className="mt-[3px] size-3.5 shrink-0" />
        {review.unverified[0]}
      </span>
    )
  }

  return (
    <div className="flex min-w-0 flex-col gap-1">
      <span className="flex items-start gap-1.5 font-medium text-fg-primary">
        <IconCheck aria-hidden className="mt-[3px] size-3.5 shrink-0 text-success" />
        {review.sentBack ? "Halon's review sent it back once, and the corrected change does what was asked" : "Halon's review: it does what was asked"}
      </span>
      {review.verified.length > 0 && <Notes title="Verified" notes={review.verified} />}
      {review.findings.length > 0 && <Notes title="Found in review" notes={review.findings} />}
      {review.unverified.length > 0 && <Notes title="Open questions" notes={review.unverified} warn />}
      {review.unreviewed.length > 0 && <Notes title="Not reviewed, since the change is too large to review whole" notes={review.unreviewed} warn />}
    </div>
  )
}
