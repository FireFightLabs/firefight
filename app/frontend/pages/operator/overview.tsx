import { router, usePage } from "@inertiajs/react"
import { IconCircleCheck, IconFlame, IconHierarchy2, IconRefresh, IconSparkles, IconStack2 } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { operatorHalonPath, operatorIncidentsPath, operatorJobsPath, operatorWorkflowsPath } from "@/lib/routes"
import { FilterBar } from "@/pages/operator/components/filter-bar"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Stat } from "@/pages/operator/components/stat"
import { percent } from "@/lib/formatters"
import { count, dollars, since } from "@/pages/operator/lib/format"
import type {
  FilterProps,
  HalonSummary,
  IncidentsSummary,
  JobsSummary,
  OperatorPageProps,
  WorkflowsSummary,
} from "@/pages/operator/types"
import type { OperatorAttentionItem } from "@/types/serializers"
import { AttentionRow } from "@/pages/operator/components/attention-row"
import { OverviewPanel } from "@/pages/operator/components/overview-panel"

interface OverviewProps extends OperatorPageProps, FilterProps {
  attentionItems: OperatorAttentionItem[]
  attentionCapped: boolean
  attentionLimit: number
  incidents: IncidentsSummary
  workflows: WorkflowsSummary
  jobs: JobsSummary | null
  halon: HalonSummary
}

function refresh() {
  router.reload()
}

export default function OperatorOverview() {
  const props = usePage<OverviewProps>().props
  const { attentionItems, attentionCapped, attentionLimit, incidents, workflows, jobs, halon, filter } = props
  const filterQuery = { window: filter.window, workspace: filter.workspace ?? undefined }
  const didNotAnswer = halon.stopped + halon.failed
  const noAnswerTone = halon.failed > 0 ? "error" : didNotAnswer > 0 ? "warning" : "neutral"

  return (
    <OperatorLayout title="Overview">
      <PageHeading
        title="Overview"
        lead="Everything Firefight did in the window, across every workspace. What needs a person is at the top, and every row opens the record behind it."
      >
        <Button type="button" variant="outline" size="sm" onClick={refresh}>
          <IconRefresh className="size-3.5" />
          Refresh
        </Button>
      </PageHeading>
      <FilterBar filter={filter} windows={props.windows} workspaces={props.workspaces} />

      <Card className="mb-6 gap-0 overflow-hidden py-0">
        <div className="flex items-baseline justify-between gap-4 border-b border-border px-5 py-4">
          <div className="flex items-baseline gap-3">
            <h2 className="text-sm font-semibold">Needs attention</h2>
            <span className="text-muted-foreground font-mono text-xs">{attentionItems.length} open</span>
          </div>
          <span className="text-muted-foreground text-xs">Failures in the window, and anything backed up or stuck now</span>
        </div>
        {attentionItems.length === 0 ? (
          <p className="text-muted-foreground flex items-center gap-2 px-5 py-8 text-sm">
            <IconCircleCheck className="size-4 text-success" />
            Nothing needs a person in this window.
          </p>
        ) : (
          <ul className="list-none">
            {attentionItems.map((item) => (
              <AttentionRow key={item.key} item={item} />
            ))}
          </ul>
        )}
        {attentionCapped && (
          <p className="text-muted-foreground border-t border-border px-5 py-3 text-xs">
            Each kind lists its latest {attentionLimit}. Open Incidents, Workflows, Jobs or Halon for the rest.
          </p>
        )}
      </Card>

      <div className="grid gap-6 xl:grid-cols-2">
        <OverviewPanel title="Incidents" icon={IconFlame} href={operatorIncidentsPath()} source="Incidents, alerts and their routing, webhook deliveries, failed calls to the chat platform">
          <Stat label="Declared" value={count(incidents.declared)} note={`${incidents.fromAlerts} from alerts`} />
          <Stat label="Platform calls failed" value={count(incidents.platformFailures)} tone={incidents.platformFailures > 0 ? "error" : "neutral"} />
          <Stat
            label="Webhooks failed"
            value={count(incidents.webhooksFailed)}
            note={`of ${count(incidents.webhooksSent)} sent`}
            tone={incidents.webhooksFailed > 0 ? "error" : "neutral"}
          />
          <Stat
            label="Alerts routing"
            value={count(incidents.alertsWaiting)}
            note={incidents.oldestAlertAt ? `oldest ${since(incidents.oldestAlertAt)}` : "none waiting"}
            tone={incidents.alertsWaiting > 0 ? "warning" : "neutral"}
          />
        </OverviewPanel>
        <OverviewPanel title="Workflows" icon={IconHierarchy2} href={operatorWorkflowsPath()} source="Workflow runs, their steps and events">
          <Stat label="Ran" value={count(workflows.ran)} note={`${workflows.kinds} kinds`} />
          <Stat label="Failed" value={count(workflows.failed)} note="attempts used up" tone={workflows.failed > 0 ? "error" : "neutral"} />
          <Stat label="Retrying" value={count(workflows.retrying)} note="waiting for another attempt" tone={workflows.retrying > 0 ? "warning" : "neutral"} />
          <Stat label="Paused" value={count(workflows.paused)} tone={workflows.paused > 0 ? "warning" : "neutral"} />
        </OverviewPanel>
        <OverviewPanel title="Jobs" icon={IconStack2} href={operatorJobsPath()} external source="The job queue, shared by every workspace">
          {jobs ? (
            <>
              <Stat label="Finished" value={count(jobs.finished)} />
              <Stat label="Failed" value={count(jobs.failed)} note="held until retried or discarded" tone={jobs.failed > 0 ? "error" : "neutral"} />
              <Stat label="Waiting" value={count(jobs.waiting)} note={jobs.oldestWaitingAt ? `oldest ${since(jobs.oldestWaitingAt)}` : "none waiting"} />
              <Stat
                label="Workers"
                value={`${jobs.workersAlive}/${jobs.workers}`}
                note={jobs.workersAlive === jobs.workers ? "all reporting" : `${jobs.workers - jobs.workersAlive} not reporting`}
                tone={jobs.workersAlive < jobs.workers || jobs.workers === 0 ? "error" : "neutral"}
              />
            </>
          ) : (
            <p className="text-muted-foreground col-span-full py-4 text-sm">The job queue could not be read.</p>
          )}
        </OverviewPanel>
        <OverviewPanel title="Halon" icon={IconSparkles} href={operatorHalonPath(filterQuery)} source="Runs, chats, the model ledger and the tool call ledger">
          <Stat label="Runs" value={count(halon.runs)} note={`and ${count(halon.chatTurns)} chat turns`} />
          <Stat label="Answered" value={percent(halon.answered, halon.finished)} note={`${halon.answered} of ${halon.finished} finished`} />
          <Stat
            label="No answer"
            value={count(didNotAnswer)}
            note={`${halon.failed} failed on our side`}
            tone={noAnswerTone}
          />
          <Stat label="Spent" value={dollars(halon.spentMicros)} note="runs and chats" />
        </OverviewPanel>
      </div>
    </OperatorLayout>
  )
}
