import { useState } from "react"
import { IconDotsVertical, IconFileImport, IconRoute } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { exportHalonWorkflowPath } from "@/lib/routes"
import type { HalonLibraryWorkflowUse } from "@/types/serializers"
import { ImportWorkflowDialog } from "@/pages/halon/components/workflow-library/import-workflow-dialog"
import { LibraryChangesSheet } from "@/pages/halon/components/workflow-library/library-changes-sheet"
import { WorkflowOrigin } from "@/pages/halon/components/workflow-library/workflow-origin"

interface WorkflowsCardProps {
  workflows: HalonLibraryWorkflowUse[]
  canManage: boolean
}

// The workspace's workflows, where each came from and whether it runs yet, each exportable as a file to share, with
// importing a file beside them.
export function WorkflowsCard({ workflows, canManage }: WorkflowsCardProps) {
  const [ importing, setImporting ] = useState(false)
  const [ changesOf, setChangesOf ] = useState<HalonLibraryWorkflowUse | null>(null)

  function openImport() {
    setImporting(true)
  }

  function closeImport() {
    setImporting(false)
  }

  function closeChanges() {
    setChangesOf(null)
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <CardTitle>Your workflows</CardTitle>
            <CardDescription className="mt-1">Export one as a file to share it, or import a file from another workspace.</CardDescription>
          </div>
          {canManage && (
            <Button size="sm" variant="outline" onClick={openImport}>
              <IconFileImport className="size-4" />
              Import a workflow
            </Button>
          )}
        </div>
      </CardHeader>
      {workflows.length === 0 ? (
        <CardContent>
          <div className="rounded-xl border border-dashed border-border px-6 py-10 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-lg bg-muted">
              <IconRoute className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No workflows yet</p>
            <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-muted-foreground">
              Use one from Firefight&apos;s library below, or import one exported from another workspace.
            </p>
          </div>
        </CardContent>
      ) : (
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="md:w-2/5">Workflow</TableHead>
                <TableHead className="hidden sm:table-cell">From</TableHead>
                <TableHead className="hidden md:table-cell">Runs</TableHead>
                <TableHead className="w-12" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {workflows.map((workflow) => (
                <TableRow key={workflow.id}>
                  <TableCell className="text-sm font-medium text-fg-primary">{workflow.name}</TableCell>
                  <TableCell className="hidden text-sm sm:table-cell">
                    <WorkflowOrigin workflow={workflow} onUpdate={() => setChangesOf(workflow)} />
                  </TableCell>
                  <TableCell className="hidden text-sm text-muted-foreground md:table-cell">
                    {workflow.published ? "Published" : "Draft only, not published yet"}
                  </TableCell>
                  <TableCell>
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="icon" className="size-8 text-muted-foreground">
                          <IconDotsVertical className="size-4" />
                          <span className="sr-only">Actions for {workflow.name}</span>
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end" className="w-56">
                        <DropdownMenuItem asChild>
                          <a href={exportHalonWorkflowPath(workflow.id)} download>Export as a file</a>
                        </DropdownMenuItem>
                        {workflow.libraryUpdate && (
                          <DropdownMenuItem onClick={() => setChangesOf(workflow)}>
                            See Firefight&apos;s version {workflow.libraryUpdate.version}
                          </DropdownMenuItem>
                        )}
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      )}
      <LibraryChangesSheet workflow={changesOf} canManage={canManage} onClose={closeChanges} />
      {canManage && <ImportWorkflowDialog open={importing} onClose={closeImport} />}
    </Card>
  )
}
