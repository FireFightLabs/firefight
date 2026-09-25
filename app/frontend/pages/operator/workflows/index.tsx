import { Link, router, usePage } from "@inertiajs/react"

import { Card } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { OPERATOR_WORKFLOW_STATES } from "@/lib/generated/constants"
import { operatorWorkflowPath, operatorWorkflowsPath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Pager } from "@/pages/operator/components/pager"
import { WorkflowState } from "@/pages/operator/components/workflow-state"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorWorkflowRow } from "@/types/serializers"

type State = OperatorWorkflowRow["state"]

interface WorkflowsProps extends OperatorPageProps {
  workflows: OperatorWorkflowRow[]
  page: number
  more: boolean
  kinds: string[]
  counts: Partial<Record<State, number>>
  filter: { state: State | null; kind: string | null }
}

const STATES: State[] = Object.values(OPERATOR_WORKFLOW_STATES)
const ALL_KINDS = ""

export default function OperatorWorkflows() {
  const { workflows, page, more, kinds, counts, filter } = usePage<WorkflowsProps>().props
  const total = Object.values(counts).reduce((sum, count) => sum + (count ?? 0), 0)

  function query(changes: { state?: State | null; kind?: string | null; page?: number }) {
    const next = { state: filter.state, kind: filter.kind, ...changes }
    return operatorWorkflowsPath({ state: next.state ?? undefined, kind: next.kind ?? undefined, page: changes.page })
  }

  function pageHref(target: number) {
    return query({ page: target })
  }

  function pickKind(event: React.ChangeEvent<HTMLSelectElement>) {
    router.visit(query({ kind: event.target.value || null }), { preserveScroll: true })
  }

  return (
    <OperatorLayout title="Workflows">
      <PageHeading
        title="Workflows"
        lead="Every workflow Firefight ran, newest first. Open one to see its steps drawn from what depends on what, its events, and to pause, resume, cancel or retry it."
      />
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Link
          href={query({ state: null })}
          preserveScroll
          className={`rounded-full border px-3 py-1 text-xs ${filter.state === null ? "border-primary/40 bg-primary/10 text-primary" : "border-border text-muted-foreground hover:text-foreground"}`}
        >
          All <span className="font-mono">{total}</span>
        </Link>
        {STATES.map((state) => (
          <Link
            key={state}
            href={query({ state })}
            preserveScroll
            className={`rounded-full border px-3 py-1 text-xs capitalize ${filter.state === state ? "border-primary/40 bg-primary/10 text-primary" : "border-border text-muted-foreground hover:text-foreground"}`}
          >
            {state} <span className="font-mono">{counts[state] ?? 0}</span>
          </Link>
        ))}
        <label className="text-muted-foreground ml-auto flex items-center gap-2 text-xs">
          Kind
          <select value={filter.kind ?? ALL_KINDS} onChange={pickKind} className="bg-card h-8 rounded-md border border-border px-2 font-mono text-xs text-foreground">
            <option value={ALL_KINDS}>All kinds</option>
            {kinds.map((kind) => (
              <option key={kind} value={kind}>{kind}</option>
            ))}
          </select>
        </label>
      </div>
      <Card className="gap-0 overflow-hidden py-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Workflow</TableHead>
              <TableHead>State</TableHead>
              <TableHead>Steps</TableHead>
              <TableHead>Started</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {workflows.map((workflow) => (
              <TableRow key={workflow.id}>
                <TableCell>
                  <Link href={operatorWorkflowPath(workflow.id)} className="flex flex-col hover:underline">
                    <span className="font-mono text-[13px]">{workflow.workflowClass}</span>
                    <span className="text-muted-foreground text-xs">{workflow.subjectLabel}</span>
                  </Link>
                </TableCell>
                <TableCell><WorkflowState state={workflow.state} /></TableCell>
                <TableCell className="text-muted-foreground">
                  <span className="font-mono">{workflow.stepsDone}/{workflow.stepsTotal}</span>
                  {workflow.failedStep && <span className="ml-2 font-mono text-xs text-rose-400">{workflow.failedStep}</span>}
                </TableCell>
                <TableCell className="text-muted-foreground">{formatDateTime(workflow.createdAt)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        {workflows.length === 0 && <p className="text-muted-foreground px-4 py-10 text-center text-sm">No workflows match.</p>}
        <Pager page={page} more={more} hrefFor={pageHref} />
      </Card>
    </OperatorLayout>
  )
}
