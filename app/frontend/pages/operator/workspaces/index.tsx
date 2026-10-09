import { Link, usePage } from "@inertiajs/react"

import { Card } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDate } from "@/lib/formatters"
import { operatorWorkspacePath, operatorWorkspacesPath } from "@/lib/routes"
import { FilterBar } from "@/pages/operator/components/filter-bar"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Pager } from "@/pages/operator/components/pager"
import { dollars } from "@/pages/operator/lib/format"
import { TONE_CLASSES } from "@/pages/operator/lib/tone"
import type { FilterProps, OperatorPageProps } from "@/pages/operator/types"
import type { OperatorWorkspaceRow } from "@/types/serializers"

interface WorkspacesProps extends OperatorPageProps, Omit<FilterProps, "workspaces"> {
  workspaces: OperatorWorkspaceRow[]
  page: number
  more: boolean
}

export default function OperatorWorkspaces() {
  const { workspaces, page, more, filter, windows } = usePage<WorkspacesProps>().props

  function pageHref(next: number) {
    return operatorWorkspacesPath({ page: next, window: filter.window })
  }

  return (
    <OperatorLayout title="Workspaces">
      <PageHeading
        title="Workspaces"
        lead="Every workspace, where its code sandboxes run, and what they cost in the window. Open one to hold it to a provider, see its failovers and what each code fix cost."
      />
      <FilterBar filter={filter} windows={windows} />
      <Card className="gap-0 overflow-hidden py-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Workspace</TableHead>
              <TableHead>Code sandboxes run on</TableHead>
              <TableHead className="text-right">Boxes</TableHead>
              <TableHead className="text-right">Sandbox cost</TableHead>
              <TableHead>Failovers</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {workspaces.map((workspace) => (
              <TableRow key={workspace.id}>
                <TableCell>
                  <Link href={operatorWorkspacePath(workspace.id, { window: filter.window })} className="flex flex-col hover:underline">
                    <span className="text-sm font-medium">{workspace.name}</span>
                    <span className="text-muted-foreground text-xs">Since {formatDate(workspace.createdAt)}</span>
                  </Link>
                </TableCell>
                <TableCell className={workspace.held ? "" : "text-muted-foreground"}>{workspace.placement}</TableCell>
                <TableCell className="text-right font-mono tabular-nums">{workspace.boxes}</TableCell>
                <TableCell className="text-right font-mono tabular-nums">{dollars(workspace.sandboxMicros)}</TableCell>
                <TableCell>
                  {workspace.failovers > 0 ? (
                    <span className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium ${TONE_CLASSES.warning}`}>
                      <span className="size-1.5 rounded-full bg-current" />
                      {workspace.failovers} to the backup
                    </span>
                  ) : (
                    <span className="text-muted-foreground text-xs">None</span>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        {workspaces.length === 0 && <p className="text-muted-foreground px-4 py-10 text-center text-sm">No workspaces yet.</p>}
        <Pager page={page} more={more} hrefFor={pageHref} labels={["Previous", "Next"]} />
      </Card>
    </OperatorLayout>
  )
}
