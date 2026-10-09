import { Link, router, usePage } from "@inertiajs/react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Card } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { OPERATOR_WORKFLOW_STATES } from "@/pages/operator/generated/constants"
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

// A kind is a workflow class name, set in mono as on the rows below.
function monoLabel(option: SearchableSelectOption) {
  return <span className={option.value === ALL_KINDS ? "" : "font-mono text-xs"}>{option.label}</span>
}

export default function OperatorWorkflows() {
  const { workflows, page, more, kinds, counts, filter } = usePage<WorkflowsProps>().props
  const total = Object.values(counts).reduce((sum, count) => sum + (count ?? 0), 0)
  const kindOptions: SearchableSelectOption[] = [ { value: ALL_KINDS, label: "All kinds" }, ...kinds.map((kind) => ({ value: kind, label: kind })) ]

  function query(changes: { state?: State | null; kind?: string | null; page?: number }) {
    const next = { state: filter.state, kind: filter.kind, ...changes }
    return operatorWorkflowsPath({ state: next.state ?? undefined, kind: next.kind ?? undefined, page: changes.page })
  }

  function pageHref(target: number) {
    return query({ page: target })
  }

  function pickKind(value: string | null) {
    router.visit(query({ kind: value || null }), { preserveScroll: true })
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
          className={`rounded-full border px-3 py-1 text-xs ${filter.state === null ? "border-brand-border bg-brand-tint text-brand" : "border-border text-fg-secondary transition-colors hover:bg-surface-hover hover:text-fg-primary"}`}
        >
          All <span className="font-mono">{total}</span>
        </Link>
        {STATES.map((state) => (
          <Link
            key={state}
            href={query({ state })}
            preserveScroll
            className={`rounded-full border px-3 py-1 text-xs capitalize ${filter.state === state ? "border-brand-border bg-brand-tint text-brand" : "border-border text-fg-secondary transition-colors hover:bg-surface-hover hover:text-fg-primary"}`}
          >
            {state} <span className="font-mono">{counts[state] ?? 0}</span>
          </Link>
        ))}
        <div className="ml-auto flex items-center gap-2">
          <Label htmlFor="operator-workflow-kind" className="text-muted-foreground text-xs font-normal">
            Kind
          </Label>
          <div className="w-72">
            <SearchableSelect
              id="operator-workflow-kind"
              value={filter.kind ?? ALL_KINDS}
              onValueChange={pickKind}
              options={kindOptions}
              searchPlaceholder="Search kinds"
              emptyText="No kind matches"
              renderOption={monoLabel}
              renderSelected={monoLabel}
            />
          </div>
        </div>
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
                  {workflow.failedStep && <span className="ml-2 font-mono text-xs text-error">{workflow.failedStep}</span>}
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
