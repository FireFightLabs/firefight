import { useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import type { HalonLibraryWorkflow } from "@/types/serializers"
import { UseLibraryWorkflowDialog } from "@/pages/halon/components/workflow-library/use-library-workflow-dialog"
import { WORKFLOW_TRIGGER_LABELS } from "@/pages/halon/lib/workflow-trigger-labels"

interface LibraryItemsCardProps {
  items: HalonLibraryWorkflow[]
  canManage: boolean
}

function stepWords(count: number): string {
  return `${count} step${count === 1 ? "" : "s"}`
}

// Firefight's own workflows, each with its version, what starts it and the workspace's workflows already made from it.
// One whose steps this Firefight cannot run yet stays listed with why.
export function LibraryItemsCard({ items, canManage }: LibraryItemsCardProps) {
  const [ using, setUsing ] = useState<HalonLibraryWorkflow | null>(null)

  function close() {
    setUsing(null)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Firefight&apos;s library</CardTitle>
        <CardDescription className="mt-1">
          Workflows Firefight ships and keeps up to date. Use one as it is and it moves with each new version, or make it your own
          copy to change.
        </CardDescription>
      </CardHeader>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="md:w-1/2">Workflow</TableHead>
              <TableHead className="hidden md:table-cell">Starts</TableHead>
              <TableHead className="hidden sm:table-cell">Version</TableHead>
              <TableHead className="w-24" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {items.map((item) => (
              <TableRow key={item.key}>
                <TableCell className="max-w-0 whitespace-normal">
                  <div className="text-sm font-medium text-fg-primary">{item.name}</div>
                  <div className="text-xs text-muted-foreground">{item.description}</div>
                  {item.usedBy.length > 0 && <div className="mt-1 text-xs text-fg-secondary">In use here as {item.usedBy.join(", ")}</div>}
                </TableCell>
                <TableCell className="hidden text-sm text-muted-foreground md:table-cell">
                  <div>{WORKFLOW_TRIGGER_LABELS[item.triggerKind]}</div>
                  <div className="text-xs">{stepWords(item.stepCount)}</div>
                </TableCell>
                <TableCell className="hidden text-sm text-muted-foreground sm:table-cell">Version {item.version}</TableCell>
                <TableCell className="text-right">
                  {canManage && (
                    <Blocked reason={item.useBlockedReason}>
                      <Button type="button" size="sm" variant="outline" disabled={Boolean(item.useBlockedReason)} onClick={() => setUsing(item)}>
                        Use
                      </Button>
                    </Blocked>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
      {canManage && <UseLibraryWorkflowDialog item={using} onClose={close} />}
    </Card>
  )
}
