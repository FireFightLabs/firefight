import { Head, Link } from "@inertiajs/react"
import {
  IconArrowLeft,
  IconDotsVertical,
  IconFlame,
  IconSparkles,
} from "@tabler/icons-react"

import { PostmortemEditor } from "@/components/postmortem-editor"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Separator } from "@/components/ui/separator"
import { incidentPath } from "@/lib/routes"

const incident = {
  id: "1",
  identifier: "INC-042",
  name: "Payment processing failures in EU region",
}

const postmortem = {
  status: "in_progress" as const,
  generatedBy: "Sarah Chen",
  createdAt: "2026-03-25T10:30:00Z",
}

const statusLabels: Record<string, string> = {
  draft: "Draft",
  in_progress: "In progress",
  in_review: "In review",
  completed: "Completed",
}

const statusStyles: Record<string, string> = {
  draft: "bg-muted text-muted-foreground",
  in_progress: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  in_review: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  completed: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
}

const postmortemContent = `<h1>Payment processing failures in EU region</h1>
<h2>Summary</h2>
<p><strong>Problem:</strong> Payment processing was degraded in the EU region due to a misconfigured rate limit on the payment gateway proxy, resulting in complete checkout failures for all EU customers starting at 07:58 UTC.</p>
<p><strong>Impact:</strong> 2,847 failed payment attempts and €142,350 in delayed revenue over 75 minutes. Customer support received 89 tickets. All revenue was recovered after resolution.</p>
<p><strong>Causes:</strong> A rate limit configuration change in PR #4285, deployed at 07:45 UTC, inadvertently reduced the payment proxy rate limit from 10,000 req/s to 100 req/s. The change was part of a larger PR and was not caught in code review.</p>
<p><strong>Steps to resolve:</strong> We rolled back the rate limit configuration to 10,000 req/s at 09:12 UTC. Payment success rates returned to normal within 3 minutes. Stripe's retry mechanism automatically processed all failed transactions.</p>

<h2>Introduction</h2>
<p>On March 25, 2026 at 07:58 UTC, our monitoring detected a sharp drop in payment success rates in the EU region. The incident was declared at 08:15 UTC by Alex Kim after multiple customer reports of failed checkouts.</p>
<p>Sarah Chen was assigned as Incident Lead and coordinated the response across the payments and platform teams. The root cause was identified at 09:10 UTC — a misconfigured rate limit on the payment gateway proxy that had been deployed 73 minutes earlier.</p>

<h2>Deeper Dive</h2>
<p>The payment gateway proxy sits between our application servers and Stripe's API. It handles rate limiting, retry logic, and request routing for all payment operations.</p>
<p>PR #4285 introduced several configuration changes to the proxy, including an update to logging levels and timeout values. Buried within these changes was a modification to the rate limit value:</p>
<pre><code>rate_limit_requests_per_second: 100  # was 10000</code></pre>
<p>This change was not intentional — it appears to have been introduced during a local testing session and accidentally committed. The PR reviewer focused on the logging and timeout changes and did not notice the rate limit modification.</p>

<h2>Impact</h2>
<ul>
<li><strong>2,847 failed payment attempts</strong> across the EU region</li>
<li><strong>€142,350 in delayed revenue</strong> (all recovered after resolution)</li>
<li><strong>75 minutes</strong> of complete checkout failure for EU customers</li>
<li><strong>89 support tickets</strong> from affected customers</li>
<li>Status page was updated at 08:30 UTC</li>
<li>No data loss — all transactions were retried successfully by Stripe</li>
</ul>

<h2>Resolution</h2>
<p>At 09:10 UTC, James Wilson identified the root cause by comparing the current proxy configuration with the previous deployment. The rate limit was rolled back to 10,000 req/s via an emergency configuration push at 09:12 UTC.</p>
<p>Payment success rates returned to 99.97% within 3 minutes. All queued and failed payments were automatically retried by Stripe and completed successfully. No manual intervention was required for transaction recovery.</p>

<h2>Key Contributing Factors</h2>
<ul>
<li>The deployment pipeline did not validate rate limit values against minimum thresholds</li>
<li>The configuration change was part of a larger PR and the rate limit change was not called out in code review</li>
<li>EU-specific monitoring alerts were set with a 15-minute delay, causing late detection</li>
<li>No pre-deployment smoke test checks payment processing in the EU region specifically</li>
</ul>

<h2>What Went Well</h2>
<ul>
<li>Incident was declared within 17 minutes of first detection</li>
<li>Root cause was identified in under 60 minutes</li>
<li>No payment data was lost — Stripe's retry mechanism handled all failed transactions</li>
<li>Cross-team collaboration was efficient with clear ownership</li>
<li>Status page was updated promptly, reducing inbound support volume</li>
</ul>

<h2>Action Items</h2>
<ul data-type="taskList">
<li data-type="taskItem" data-checked="false">Add rate limit validation to CI pipeline — reject values below 1,000 req/s</li>
<li data-type="taskItem" data-checked="false">Create runbook for payment proxy configuration changes</li>
<li data-type="taskItem" data-checked="false">Reduce EU monitoring alert delay from 15 minutes to 2 minutes</li>
<li data-type="taskItem" data-checked="false">Add payment success rate widget to the main on-call dashboard</li>
<li data-type="taskItem" data-checked="false">Implement pre-deployment smoke test for EU payment processing</li>
</ul>`

export default function PostmortemPage() {
  return (
    <>
      <Head title={`Postmortem — ${incident.identifier}`} />
      <div className="min-h-screen bg-background">
        {/* Minimal header bar */}
        <header className="sticky top-0 z-50 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
          <div className="mx-auto flex h-12 max-w-4xl items-center gap-3 px-4 lg:px-6">
            <Link href={incidentPath(incident.id)} className="text-muted-foreground hover:text-foreground">
              <IconArrowLeft className="size-4" />
            </Link>
            <Separator orientation="vertical" className="h-4" />
            <nav className="flex items-center gap-1.5 text-sm text-muted-foreground overflow-hidden">
              <IconFlame className="size-4 shrink-0 text-primary" />
              <span className="hidden sm:inline">Incidents</span>
              <span className="hidden sm:inline">›</span>
              <span className="font-medium hidden sm:inline">{incident.identifier}</span>
              <span className="hidden sm:inline">›</span>
              <span className="truncate font-medium text-foreground">
                Postmortem
              </span>
            </nav>
            <div className="ml-auto flex items-center gap-2">
              <Badge
                variant="secondary"
                className={`text-xs ${statusStyles[postmortem.status]}`}
              >
                {statusLabels[postmortem.status]}
              </Badge>
              <Button variant="outline" size="sm">
                Review
              </Button>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon" className="size-8">
                    <IconDotsVertical className="size-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem>Export as PDF</DropdownMenuItem>
                  <DropdownMenuItem>Export as Markdown</DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem>
                    <IconSparkles className="size-4" />
                    AI Rewrite
                  </DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem>Mark as Completed</DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>
        </header>

        {/* Editor area — clean, distraction-free */}
        <main className="mx-auto max-w-3xl px-4 py-12 lg:px-6">
          <PostmortemEditor content={postmortemContent} />
        </main>
      </div>
    </>
  )
}
