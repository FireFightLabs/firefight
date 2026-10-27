import { Head, usePage } from "@inertiajs/react"
import { IconGitPullRequest } from "@tabler/icons-react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { newTabAttributes } from "@/lib/links"
import { PreventedEvidence } from "@/pages/halon/components/prevented-evidence"
import type { PullRequestReviewFinding, PullRequestReviewPage } from "@/types/serializers"
import type { SharedProps } from "@/types"

const SHORT_SHA = 7

interface PullRequestReviewPageProps extends SharedProps {
  review: PullRequestReviewPage
  findings: PullRequestReviewFinding[]
}

// Where in the code a finding is, such as "app/models/order.rb line 42".
function place(finding: PullRequestReviewFinding): string | null {
  if (!finding.path) {
    return null
  }
  return finding.line ? `${finding.path} line ${finding.line}` : finding.path
}

// What the review read and found, such as "Halon's review of 1cb47a9. 2 findings."
function reviewed(review: PullRequestReviewPage, count: number): string {
  const found = count === 0 ? "It found no problems." : `${count} ${count === 1 ? "finding" : "findings"}.`
  return `Halon's review of ${review.headSha.slice(0, SHORT_SHA)}. ${found}`
}

// Where a finding stands now, such as "Fixed in 1cb47a9", or null while it is open.
function standing(finding: PullRequestReviewFinding): string | null {
  if (finding.fixedInSha) {
    return `Fixed in ${finding.fixedInSha.slice(0, SHORT_SHA)}`
  }
  if (finding.withdrawnReason) {
    return `Withdrawn. ${finding.withdrawnReason}`
  }
  return null
}

function FindingCard({ finding }: { finding: PullRequestReviewFinding }) {
  const where = place(finding)
  const state = standing(finding)

  return (
    <Card id={`finding-${finding.id}`} className="scroll-mt-20">
      <CardHeader>
        <div className="flex flex-wrap gap-1.5">
          <Badge variant="outline">{finding.category}</Badge>
          <Badge variant="outline">{finding.severity}</Badge>
          <Badge variant="outline">{finding.effort}</Badge>
          {finding.serious && <Badge variant="secondary">Serious</Badge>}
        </div>
        <CardTitle className="mt-2">{finding.claim}</CardTitle>
        {where && <CardDescription className="mt-1 font-mono text-xs">{where}</CardDescription>}
      </CardHeader>
      <CardContent className="flex max-w-prose flex-col gap-4 text-sm text-fg-body">
        {state && <p className="font-medium text-fg-primary">{state}</p>}
        <p>{finding.why}</p>
        {finding.failureChain.length > 0 && (
          <div>
            <p className="font-medium text-fg-primary">How it fails</p>
            <ol className="mt-1 list-decimal pl-5">
              {finding.failureChain.map((step) => (
                <li key={step}>{step}</li>
              ))}
            </ol>
          </div>
        )}
        {finding.evidence.length > 0 && (
          <div>
            <p className="font-medium text-fg-primary">Evidence</p>
            <ul className="mt-1 flex flex-col gap-1">
              {finding.evidence.map((item) => (
                <PreventedEvidence key={`${item.kind}-${item.title}`} evidence={item} />
              ))}
            </ul>
          </div>
        )}
        {finding.suggestedFix && (
          <div>
            <p className="font-medium text-fg-primary">Suggested fix</p>
            <p className="mt-1 whitespace-pre-wrap">{finding.suggestedFix}</p>
          </div>
        )}
        {finding.commentUrl && (
          <a href={finding.commentUrl} {...newTabAttributes(finding.commentUrl)} className="text-link underline underline-offset-2">
            Open the comment on the pull request
          </a>
        )}
      </CardContent>
    </Card>
  )
}

export default function PullRequestReview() {
  const { review, findings } = usePage<PullRequestReviewPageProps>().props
  const name = `${review.repository} #${review.number}`

  return (
    <AuthenticatedLayout title={name}>
      <Head title={name} />

      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <IconGitPullRequest className="size-4 text-fg-secondary" />
              {review.url ? (
                <a href={review.url} {...newTabAttributes(review.url)} className="hover:underline">
                  {name}
                </a>
              ) : (
                name
              )}
            </CardTitle>
            {review.title && <CardDescription className="mt-1">{review.title}</CardDescription>}
          </CardHeader>
          <CardContent className="flex max-w-prose flex-col gap-3 text-sm text-fg-body">
            <p>{reviewed(review, findings.length)}</p>
            {review.errorSummary && <p>It stopped: {review.errorSummary}</p>}
            {review.risk && (
              <p>
                <span className="font-medium text-fg-primary">Risk: {review.risk}.</span> {review.riskReason}
              </p>
            )}
            {review.summary && <p>{review.summary}</p>}
          </CardContent>
        </Card>

        {findings.map((finding) => (
          <FindingCard key={finding.id} finding={finding} />
        ))}
      </div>
    </AuthenticatedLayout>
  )
}
