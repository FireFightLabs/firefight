import { Link, router, usePage } from "@inertiajs/react"
import {
  IconAlertTriangle,
  IconArrowRight,
  IconCircleCheck,
  IconFlame,
  IconHierarchy2,
  IconRefresh,
  IconSparkles,
  IconStack2,
  type Icon,
} from "@tabler/icons-react"
import type { ReactNode } from "react"

import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { formatDateTime } from "@/lib/formatters"
import { OPERATOR_PROCESS_TONES } from "@/lib/generated/constants"
import { operatorHalonPath, operatorIncidentsPath, operatorJobsPath, operatorWorkflowsPath } from "@/lib/routes"
import { FilterBar } from "@/pages/operator/components/filter-bar"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Stat } from "@/pages/operator/components/stat"
import { count, dollars, percent, since } from "@/pages/operator/lib/format"
import { processToneClasses } from "@/pages/operator/lib/tone"
import type {
  FilterProps,
  HalonSummary,
  IncidentsSummary,
  JobsSummary,
  OperatorPageProps,
  WorkflowsSummary,
} from "@/pages/operator/types"
import type { OperatorAttentionItem } from "@/types/serializers"

interface OverviewProps extends OperatorPageProps, FilterProps {
  attentionItems: OperatorAttentionItem[]
  incidents: IncidentsSummary
  workflows: WorkflowsSummary
  jobs: JobsSummary | null
  halon: HalonSummary
}

function refresh() {
  router.reload()
}

function AttentionRow({ item }: { item: OperatorAttentionItem }) {
  const bad = item.tone === OPERATOR_PROCESS_TONES.BAD
  const open = (
    <>
      Open
      <IconArrowRight className="size-3.5" />
    </>
  )
  const openClass = "inline-flex items-center gap-1 rounded-md border border-border px-2.5 py-1 text-xs text-muted-foreground hover:text-foreground"

  return (
    <li className="grid grid-cols-[28px_minmax(0,1fr)_auto] items-start gap-4 border-b border-border px-5 py-3.5 last:border-b-0">
      <span className={`mt-0.5 flex size-7 items-center justify-center rounded-full border ${processToneClasses(item.tone)}`}>
        <IconAlertTriangle className="size-3.5" stroke={1.8} />
      </span>
      <div className="flex min-w-0 flex-col gap-0.5">
        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
          <span className={`text-sm font-medium ${bad ? "text-rose-600 dark:text-rose-400" : ""}`}>{item.title}</span>
          <span className="truncate font-mono text-[13px]">{item.subject}</span>
          <span className="text-muted-foreground text-xs">{item.place}</span>
        </div>
        {item.detail && <p className="text-muted-foreground text-[13px]">{item.detail}</p>}
      </div>
      <div className="flex items-center gap-4">
        <time dateTime={item.at} title={formatDateTime(item.at)} className="text-muted-foreground font-mono text-xs">
          {since(item.at)}
        </time>
        {item.href && (item.external ? <a href={item.href} className={openClass}>{open}</a> : <Link href={item.href} className={openClass}>{open}</Link>)}
      </div>
    </li>
  )
}

interface PanelProps {
  title: string
  icon: Icon
  href: string
  source: string
  external?: boolean
  children: ReactNode
}

function Panel({ title, icon: PanelIcon, href, source, external, children }: PanelProps) {
  const view = (
    <>
      View
      <IconArrowRight className="size-3.5" />
    </>
  )
  const viewClass = "text-muted-foreground hover:text-foreground inline-flex items-center gap-1 text-xs"

  return (
    <Card className="gap-4 px-5 py-5">
      <div className="flex items-center justify-between">
        <h2 className="flex items-center gap-2 text-sm font-semibold">
          <PanelIcon className="text-primary size-4" stroke={1.7} />
          {title}
        </h2>
        {external ? <a href={href} className={viewClass}>{view}</a> : <Link href={href} className={viewClass}>{view}</Link>}
      </div>
      <div className="grid grid-cols-2 gap-3">{children}</div>
      <p className="text-muted-foreground/80 text-xs">{source}</p>
    </Card>
  )
}

export default function OperatorOverview() {
  const props = usePage<OverviewProps>().props
  const { attentionItems, incidents, workflows, jobs, halon, filter } = props
  const filterQuery = { window: filter.window, workspace: filter.workspace ?? undefined }
  const didNotAnswer = halon.stopped + halon.failed
  const noAnswerTone = halon.failed > 0 ? "rose" : didNotAnswer > 0 ? "amber" : "neutral"

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
            <IconCircleCheck className="size-4 text-emerald-500" />
            Nothing needs a person in this window.
          </p>
        ) : (
          <ul className="list-none">
            {attentionItems.map((item) => (
              <AttentionRow key={item.key} item={item} />
            ))}
          </ul>
        )}
      </Card>

      <div className="grid gap-6 xl:grid-cols-2">
        <Panel title="Incidents" icon={IconFlame} href={operatorIncidentsPath()} source="Incidents, alerts and their routing, webhook deliveries, failed calls to the chat platform">
          <Stat label="Declared" value={count(incidents.declared)} note={`${incidents.fromAlerts} from alerts`} />
          <Stat label="Platform calls failed" value={count(incidents.platformFailures)} tone={incidents.platformFailures > 0 ? "rose" : "neutral"} />
          <Stat
            label="Webhooks failed"
            value={count(incidents.webhooksFailed)}
            note={`of ${count(incidents.webhooksSent)} sent`}
            tone={incidents.webhooksFailed > 0 ? "rose" : "neutral"}
          />
          <Stat
            label="Alerts routing"
            value={count(incidents.alertsWaiting)}
            note={incidents.oldestAlertAt ? `oldest ${since(incidents.oldestAlertAt)}` : "none waiting"}
            tone={incidents.alertsWaiting > 0 ? "amber" : "neutral"}
          />
        </Panel>
        <Panel title="Workflows" icon={IconHierarchy2} href={operatorWorkflowsPath()} source="Workflow runs, their steps and events">
          <Stat label="Ran" value={count(workflows.ran)} note={`${workflows.kinds} kinds`} />
          <Stat label="Failed" value={count(workflows.failed)} note="attempts used up" tone={workflows.failed > 0 ? "rose" : "neutral"} />
          <Stat label="Retrying" value={count(workflows.retrying)} note="waiting for another attempt" tone={workflows.retrying > 0 ? "amber" : "neutral"} />
          <Stat label="Paused" value={count(workflows.paused)} tone={workflows.paused > 0 ? "amber" : "neutral"} />
        </Panel>
        <Panel title="Jobs" icon={IconStack2} href={operatorJobsPath()} external source="The job queue, shared by every workspace">
          {jobs ? (
            <>
              <Stat label="Finished" value={count(jobs.finished)} />
              <Stat label="Failed" value={count(jobs.failed)} note="held until retried or discarded" tone={jobs.failed > 0 ? "rose" : "neutral"} />
              <Stat label="Waiting" value={count(jobs.waiting)} note={jobs.oldestWaitingAt ? `oldest ${since(jobs.oldestWaitingAt)}` : "none waiting"} />
              <Stat
                label="Workers"
                value={`${jobs.workersAlive}/${jobs.workers}`}
                note={jobs.workersAlive === jobs.workers ? "all reporting" : `${jobs.workers - jobs.workersAlive} not reporting`}
                tone={jobs.workersAlive < jobs.workers || jobs.workers === 0 ? "rose" : "neutral"}
              />
            </>
          ) : (
            <p className="text-muted-foreground col-span-full py-4 text-sm">The job queue could not be read.</p>
          )}
        </Panel>
        <Panel title="Halon" icon={IconSparkles} href={operatorHalonPath(filterQuery)} source="Runs, chats, the model ledger and the tool call ledger">
          <Stat label="Runs" value={count(halon.runs)} note={`and ${count(halon.chatTurns)} chat turns`} />
          <Stat label="Answered" value={percent(halon.answered, halon.finished)} note={`${halon.answered} of ${halon.finished} finished`} />
          <Stat
            label="No answer"
            value={count(didNotAnswer)}
            note={`${halon.failed} failed on our side`}
            tone={noAnswerTone}
          />
          <Stat label="Spent" value={dollars(halon.spentMicros)} note="runs and chats" />
        </Panel>
      </div>
    </OperatorLayout>
  )
}
