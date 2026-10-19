import { useState } from "react"
import { Link, router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { TableCell, TableHead } from "@/components/ui/table"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { OptionsTable } from "@/components/options-table"
import { allowancePath, halonOnCallPath } from "@/lib/routes"
import { AllowanceDialog } from "@/pages/settings/components/workspace/allowance-dialog"
import type { Allowance, AllowanceChoice, EnvironmentOption } from "@/types/serializers"

type DialogState = { open: false } | { open: true; allowance: Allowance | null }

function timesUsed(count: number): string {
  if (count === 0) {
    return "Not yet"
  }
  return count === 1 ? "Once" : `${count} times`
}

// What Halon may do without asking in anyone's chat, beside the switch for safe changes in the Halon card above. Each
// row turns on and off, edits in a dialog and deletes after asking, and one Halon already acted under is turned off
// instead.
export function AllowancesCard({
  allowances,
  capabilities,
  tools,
  environments,
  canManage,
}: {
  allowances: Allowance[]
  capabilities: AllowanceChoice[]
  tools: AllowanceChoice[]
  environments: EnvironmentOption[]
  canManage: boolean
}) {
  const [dialog, setDialog] = useState<DialogState>({ open: false })
  const [deleting, setDeleting] = useState<Allowance | null>(null)

  function toggle(allowance: Allowance) {
    router.patch(allowancePath(allowance.id), { allowance: { enabled: !allowance.enabled } }, { preserveScroll: true })
  }

  function edit(allowance: Allowance) {
    setDialog({ open: true, allowance })
  }

  function openNew() {
    setDialog({ open: true, allowance: null })
  }

  function closeDialog() {
    setDialog({ open: false })
  }

  function cancelDelete() {
    setDeleting(null)
  }

  function confirmDelete() {
    if (!deleting) {
      return
    }
    router.delete(allowancePath(deleting.id), { preserveScroll: true, onFinish: cancelDelete })
  }

  function usedCells(allowance: Allowance) {
    return (
      <>
        <TableCell className="text-muted-foreground text-sm">{allowance.createdByName ?? "-"}</TableCell>
        <TableCell className="text-muted-foreground text-sm">{timesUsed(allowance.usageCount)}</TableCell>
      </>
    )
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-3 space-y-0">
        <div className="min-w-0">
          <CardTitle>Halon may do these without asking</CardTitle>
          <CardDescription className="mt-1">
            Risky changes Halon makes in anyone&apos;s chat without asking first, such as rolling back deploys in Staging.
            It says what it did in the chat, and each one is in the activity log with the entry that allowed it. Approval
            rules still ask their approvers, and changes to who can reach something or to a secret always ask a person.
            When nobody is around, Halon acts only under the{" "}
            <Link href={halonOnCallPath()} className="underline underline-offset-4">
              unattended rules on On-call
            </Link>
            .
          </CardDescription>
        </div>
        {canManage && (
          <Button size="sm" onClick={openNew}>
            Add
          </Button>
        )}
      </CardHeader>
      <CardContent className={allowances.length === 0 ? "" : "p-0"}>
        {allowances.length === 0 ? (
          <p className="text-muted-foreground py-6 text-center text-sm">
            Nothing yet. Every risky change asks the person in the chat, unless they allow it for the rest of that chat.
          </p>
        ) : (
          <OptionsTable
            options={allowances}
            nameHeader="Change"
            headers={
              <>
                <TableHead className="w-36">Added by</TableHead>
                <TableHead className="w-28">Used</TableHead>
              </>
            }
            cells={usedCells}
            onToggleEnabled={toggle}
            onEdit={edit}
            onDelete={setDeleting}
            readOnly={!canManage}
          />
        )}
      </CardContent>

      <AllowanceDialog
        key={dialog.open ? (dialog.allowance?.id ?? "new") : "closed"}
        open={dialog.open}
        allowance={dialog.open ? dialog.allowance : null}
        capabilities={capabilities}
        tools={tools}
        environments={environments}
        onDismiss={closeDialog}
      />

      <ConfirmDeleteDialog
        open={deleting !== null}
        title="Delete this entry?"
        description={deleting ? `"${deleting.name}" comes off the list, and Halon asks the person before it again.` : ""}
        onConfirm={confirmDelete}
        onCancel={cancelDelete}
      />
    </Card>
  )
}
