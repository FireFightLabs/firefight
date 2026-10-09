import { useMemo, useState } from "react"
import { router } from "@inertiajs/react"

import type { AbilityActionOption, AbilityRole, ApprovalRule } from "@/types/serializers"
import { abilityRolePath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { andList } from "@/lib/formatters"
import { ActionLabel } from "@/pages/settings/components/permissions/action-label"
import { RequiresApprovalBadge } from "@/pages/settings/components/permissions/requires-approval-badge"
import { RISK_VARIANT } from "@/pages/settings/components/permissions/risk"
import { useGroupedActions } from "@/pages/settings/components/permissions/use-grouped-actions"

function counted(count: number, one: string, many: string): string | null {
  if (count === 0) {
    return null
  }
  return `${count} ${count === 1 ? one : many}`
}

// Names who loses what the set gives, since deleting revokes every grant of it at once.
function deleteDescription(set: AbilityRole): string {
  const holders = [
    counted(set.peopleCount, "person", "people"),
    counted(set.keyCount, "service key", "service keys"),
    counted(set.agentCount, "agent", "agents"),
  ].filter((holder): holder is string => holder !== null)

  if (holders.length === 0) {
    return "Nobody holds it, so nobody loses anything."
  }
  return `It is revoked from ${andList(holders)} straight away, and they lose what it gives. This cannot be undone.`
}

export function SetEditor({
  set,
  actions,
  approvalRules,
  canManage,
}: {
  set: AbilityRole
  actions: AbilityActionOption[]
  approvalRules: ApprovalRule[]
  canManage: boolean
}) {
  const [search, setSearch] = useState("")
  const [confirmingDelete, setConfirmingDelete] = useState(false)

  // A built-in pack is kept in step by Firefight, so it lists what it holds and is never edited here.
  const canEdit = canManage && !set.editBlockedReason
  const shown = useMemo(
    () => (set.builtIn ? actions.filter((action) => set.actionIds.includes(action.id)) : actions),
    [actions, set.builtIn, set.actionIds],
  )
  const grouped = useGroupedActions(shown, search)

  function toggle(actionId: string) {
    const next = set.actionIds.includes(actionId)
      ? set.actionIds.filter((id) => id !== actionId)
      : [...set.actionIds, actionId]

    router.patch(abilityRolePath(set.id), { action_ids: next }, { preserveScroll: true })
  }

  function toggleGroup(entries: AbilityActionOption[]) {
    const ids = entries.map((action) => action.id)
    const allOn = ids.every((id) => set.actionIds.includes(id))
    const next = allOn
      ? set.actionIds.filter((id) => !ids.includes(id))
      : [...new Set([...set.actionIds, ...ids])]

    router.patch(abilityRolePath(set.id), { action_ids: next }, { preserveScroll: true })
  }

  function askToDelete() {
    setConfirmingDelete(true)
  }

  function stopDeleting() {
    setConfirmingDelete(false)
  }

  function deleteSet() {
    router.delete(abilityRolePath(set.id), { preserveScroll: true, onFinish: stopDeleting })
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-3 space-y-0">
        <div className="min-w-0">
          <CardTitle className="text-base">{set.name}</CardTitle>
          {set.description && <p className="text-muted-foreground text-sm">{set.description}</p>}
          <p className="text-muted-foreground text-xs">
            {set.actionIds.length} {set.actionIds.length === 1 ? "ability" : "abilities"} ·{" "}
            {set.grantCount === 0
              ? "not granted to anyone yet"
              : `granted ${set.grantCount} ${set.grantCount === 1 ? "time" : "times"}`}
          </p>
        </div>
        {canManage && (
          <Blocked reason={set.deleteBlockedReason ?? undefined}>
            <Button
              size="sm"
              variant="ghost"
              className="text-destructive shrink-0"
              disabled={Boolean(set.deleteBlockedReason)}
              onClick={askToDelete}
            >
              Delete set
            </Button>
          </Blocked>
        )}
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {set.editBlockedReason && (
          <div className="border-border bg-muted/40 text-muted-foreground rounded-lg border px-3 py-2 text-xs">
            {set.editBlockedReason}
          </div>
        )}

        {set.grantCount > 0 && canEdit && (
          <div className="border-border bg-muted/40 text-muted-foreground rounded-lg border px-3 py-2 text-xs">
            Changing this set changes what everyone holding it can do, immediately.
          </div>
        )}

        <Input
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search abilities…"
        />

        <div className="border-border max-h-[28rem] overflow-y-auto rounded-lg border">
          {grouped.length === 0 ? (
            <p className="text-muted-foreground px-3 py-6 text-center text-sm">No abilities match.</p>
          ) : (
            grouped.map(([group, entries]) => (
              <div key={group}>
                <div className="bg-muted/50 flex items-center justify-between gap-2 px-3 py-1.5">
                  <p className="text-muted-foreground text-xs font-medium">{group}</p>
                  {canEdit && (
                    <button
                      type="button"
                      onClick={() => toggleGroup(entries)}
                      className="text-muted-foreground hover:text-foreground text-xs"
                    >
                      {entries.every((action) => set.actionIds.includes(action.id))
                        ? "Clear"
                        : "Select all"}
                    </button>
                  )}
                </div>
                {entries.map((action) => (
                  <label
                    key={action.id}
                    className={`flex items-center gap-3 px-3 py-2 ${canEdit ? "hover:bg-muted/50 cursor-pointer" : ""}`}
                  >
                    <Checkbox
                      checked={set.actionIds.includes(action.id)}
                      disabled={!canEdit}
                      onCheckedChange={() => toggle(action.id)}
                    />
                    <ActionLabel actionKey={action.key} title={action.title} description={action.description} />
                    <RequiresApprovalBadge action={action} rules={approvalRules} />
                    <Badge variant={RISK_VARIANT[action.riskLevel] ?? "secondary"} className="shrink-0">
                      {action.riskLevel}
                    </Badge>
                  </label>
                ))}
              </div>
            ))
          )}
        </div>
      </CardContent>
      <ConfirmDeleteDialog
        open={confirmingDelete}
        title={`Delete ${set.name}?`}
        description={deleteDescription(set)}
        confirmLabel="Delete set"
        onConfirm={deleteSet}
        onCancel={stopDeleting}
      />
    </Card>
  )
}
