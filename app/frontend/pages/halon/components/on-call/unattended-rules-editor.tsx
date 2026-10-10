import { useState } from "react"
import { IconAlertTriangle } from "@tabler/icons-react"
import { router } from "@inertiajs/react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { RowActions } from "@/components/row-actions"
import { unattendedRulePath } from "@/lib/routes"
import { UnattendedRuleDialog } from "@/pages/halon/components/on-call/unattended-rule-dialog"
import type { UnattendedRule, UnattendedRuleResource } from "@/types/serializers"

type DialogState = { open: false } | { open: true; rule: UnattendedRule | null }

function timesActed(count: number): string {
  if (count === 0) {
    return "Not yet"
  }
  return count === 1 ? "Once" : `${count} times`
}

export function UnattendedRulesEditor({
  rules,
  resources,
  investigator,
  canManage,
}: {
  rules: UnattendedRule[]
  resources: UnattendedRuleResource[]
  investigator: string
  canManage: boolean
}) {
  const [dialog, setDialog] = useState<DialogState>({ open: false })
  const [deleting, setDeleting] = useState<UnattendedRule | null>(null)

  function toggleRule(rule: UnattendedRule, enabled: boolean) {
    router.patch(unattendedRulePath(rule.id), { rule: { enabled } }, { preserveScroll: true })
  }

  function confirmDelete() {
    if (!deleting) {
      return
    }
    router.delete(unattendedRulePath(deleting.id), { preserveScroll: true, onFinish: () => setDeleting(null) })
  }

  function openNew() {
    setDialog({ open: true, rule: null })
  }

  function closeDialog() {
    setDialog({ open: false })
  }

  function cancelDelete() {
    setDeleting(null)
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-3 space-y-0">
        <div className="min-w-0">
          <CardTitle className="text-base">Unattended rules</CardTitle>
          <p className="text-muted-foreground text-xs">
            Changes Halon may make on its own when an alert starts it and nobody is there to apply its fix. Each one is
            checked against a fresh reading first, said in the incident with how to undo it, and kept in the activity log.
          </p>
        </div>
        {canManage && (
          <Button size="sm" onClick={openNew}>
            Add rule
          </Button>
        )}
      </CardHeader>
      <CardContent className={rules.length === 0 ? "" : "p-0"}>
        {rules.length === 0 ? (
          <p className="text-muted-foreground py-6 text-center text-sm">
            No unattended rules. Every fix Halon proposes waits for someone to apply it.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead>Rule</TableHead>
                <TableHead className="w-28">Acted</TableHead>
                <TableHead className="w-16 text-center">On</TableHead>
                <TableHead className="w-12" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {rules.map((rule) => (
                <TableRow key={rule.id} className={rule.enabled ? "" : "opacity-50"}>
                  <TableCell className="max-w-md text-sm">
                    <span className="block">{rule.sentence}</span>
                    {rule.createdByName && <span className="text-muted-foreground block text-xs">Set by {rule.createdByName}</span>}
                    {rule.blockedReason && (
                      <span className="mt-1 flex items-start gap-1.5 text-xs text-amber-600 dark:text-amber-400">
                        <IconAlertTriangle className="mt-px size-3.5 shrink-0" />
                        {rule.blockedReason}
                      </span>
                    )}
                  </TableCell>
                  <TableCell className="text-muted-foreground text-sm">{timesActed(rule.usageCount)}</TableCell>
                  <TableCell className="text-center">
                    {canManage ? (
                      <Switch
                        checked={rule.enabled}
                        onCheckedChange={(enabled) => toggleRule(rule, enabled)}
                        aria-label={`${rule.sentence} on`}
                      />
                    ) : (
                      <Badge variant={rule.enabled ? "default" : "secondary"}>{rule.enabled ? "On" : "Off"}</Badge>
                    )}
                  </TableCell>
                  <TableCell>
                    {canManage && (
                      <RowActions
                        onEdit={() => setDialog({ open: true, rule })}
                        onDelete={() => setDeleting(rule)}
                        deleteDisabledReason={rule.deleteBlockedReason}
                      />
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>

      <UnattendedRuleDialog
        key={dialog.open ? (dialog.rule?.id ?? "new") : "closed"}
        open={dialog.open}
        rule={dialog.open ? dialog.rule : null}
        resources={resources}
        investigator={investigator}
        onDismiss={closeDialog}
      />

      <ConfirmDeleteDialog
        open={deleting !== null}
        title="Delete unattended rule?"
        description={
          deleting
            ? `${deleting.sentence} Halon stops making this change on its own, and a fix that proposes it waits for someone to apply it.`
            : ""
        }
        onConfirm={confirmDelete}
        onCancel={cancelDelete}
      />
    </Card>
  )
}
