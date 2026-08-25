import { useState } from "react"
import { IconArrowDown, IconArrowUp } from "@tabler/icons-react"
import { router } from "@inertiajs/react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { approvalRulePath, moveDownApprovalRulePath, moveUpApprovalRulePath } from "@/lib/routes"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { RowActions } from "@/pages/settings/components/row-actions"
import { ApprovalRuleDialog } from "@/pages/settings/components/permissions/approval-rule-dialog"
import {
  describeApprovers,
  describeScope,
  NOTIFY_LABELS,
} from "@/pages/settings/components/permissions/approval-rule-form"
import type { AbilityActionOption, ApprovalRule, EnvironmentOption, WorkspaceMembership } from "@/types/serializers"

type DialogState = { open: false } | { open: true; rule: ApprovalRule | null }

export function ApprovalRulesEditor({
  rules,
  actions,
  environments,
  members,
  canManage,
}: {
  rules: ApprovalRule[]
  actions: AbilityActionOption[]
  environments: EnvironmentOption[]
  members: WorkspaceMembership[]
  canManage: boolean
}) {
  const [dialog, setDialog] = useState<DialogState>({ open: false })
  const [deleting, setDeleting] = useState<ApprovalRule | null>(null)

  function toggleRule(rule: ApprovalRule, enabled: boolean) {
    router.patch(approvalRulePath(rule.id), { rule: { enabled } }, { preserveScroll: true })
  }

  function moveRule(rule: ApprovalRule, direction: "up" | "down") {
    const path = direction === "up" ? moveUpApprovalRulePath(rule.id) : moveDownApprovalRulePath(rule.id)
    router.patch(path, {}, { preserveScroll: true })
  }

  function confirmDelete() {
    if (!deleting) {
      return
    }
    router.delete(approvalRulePath(deleting.id), { preserveScroll: true, onFinish: () => setDeleting(null) })
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-3 space-y-0">
        <div className="min-w-0">
          <CardTitle className="text-base">Approval rules</CardTitle>
          <p className="text-muted-foreground text-xs">
            Nothing waits for approval until a rule says so. The first matching rule decides.
          </p>
        </div>
        {canManage && (
          <Button size="sm" onClick={() => setDialog({ open: true, rule: null })}>
            Add rule
          </Button>
        )}
      </CardHeader>
      <CardContent className={rules.length === 0 ? "" : "p-0"}>
        {rules.length === 0 ? (
          <p className="text-muted-foreground py-6 text-center text-sm">
            No approval rules. Every granted ability runs as soon as it is called.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead className="w-12">Order</TableHead>
                <TableHead>Holds</TableHead>
                <TableHead>Approved by</TableHead>
                <TableHead>Asked in</TableHead>
                <TableHead className="w-16 text-center">On</TableHead>
                <TableHead className="w-32" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {rules.map((rule, index) => (
                <TableRow key={rule.id} className={rule.enabled ? "" : "opacity-50"}>
                  <TableCell className="text-muted-foreground font-mono text-xs">{index + 1}</TableCell>
                  <TableCell className="max-w-sm text-sm">
                    <span className="block truncate">{describeScope(rule, environments)}</span>
                  </TableCell>
                  <TableCell className="text-sm">
                    <span className="block truncate">{describeApprovers(rule, members)}</span>
                    {!rule.selfApproval && (
                      <span className="text-muted-foreground text-xs">not the requester</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline">{NOTIFY_LABELS[rule.notify]}</Badge>
                  </TableCell>
                  <TableCell className="text-center">
                    {canManage ? (
                      <Switch
                        checked={rule.enabled}
                        onCheckedChange={(enabled) => toggleRule(rule, enabled)}
                        aria-label={`Rule ${index + 1} enabled`}
                      />
                    ) : (
                      <Badge variant={rule.enabled ? "default" : "secondary"}>{rule.enabled ? "On" : "Off"}</Badge>
                    )}
                  </TableCell>
                  <TableCell>
                    {canManage && (
                      <div className="flex items-center justify-end gap-0.5">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="text-muted-foreground size-7"
                          title="Move up"
                          aria-label="Move rule up"
                          disabled={index === 0}
                          onClick={() => moveRule(rule, "up")}
                        >
                          <IconArrowUp className="size-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="text-muted-foreground size-7"
                          title="Move down"
                          aria-label="Move rule down"
                          disabled={index === rules.length - 1}
                          onClick={() => moveRule(rule, "down")}
                        >
                          <IconArrowDown className="size-4" />
                        </Button>
                        <RowActions onEdit={() => setDialog({ open: true, rule })} onDelete={() => setDeleting(rule)} />
                      </div>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>

      <ApprovalRuleDialog
        key={dialog.open ? (dialog.rule?.id ?? "new") : "closed"}
        open={dialog.open}
        rule={dialog.open ? dialog.rule : null}
        actions={actions}
        environments={environments}
        members={members}
        onDismiss={() => setDialog({ open: false })}
      />

      <ConfirmDeleteDialog
        open={deleting !== null}
        title="Delete approval rule?"
        description={
          deleting
            ? `${describeScope(deleting, environments)} will run without waiting for anyone. Requests already waiting keep their approvers.`
            : ""
        }
        onConfirm={confirmDelete}
        onCancel={() => setDeleting(null)}
      />
    </Card>
  )
}
