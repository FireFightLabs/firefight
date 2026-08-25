import { useState } from "react"
import { router } from "@inertiajs/react"

import type { AbilityActionOption, AbilityRole, ApprovalRule } from "@/types/serializers"
import { abilityRolePath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { RequiresApprovalBadge } from "@/pages/settings/components/permissions/requires-approval-badge"
import { RISK_VARIANT } from "@/pages/settings/components/permissions/risk"
import { useGroupedActions } from "@/pages/settings/components/permissions/use-grouped-actions"

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

  const grouped = useGroupedActions(actions, search)

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

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-3 space-y-0">
        <div className="min-w-0">
          <CardTitle className="text-base">{set.name}</CardTitle>
          <p className="text-muted-foreground text-xs">
            {set.actionIds.length} {set.actionIds.length === 1 ? "ability" : "abilities"} ·{" "}
            {set.grantCount === 0
              ? "not granted to anyone yet"
              : `granted ${set.grantCount} ${set.grantCount === 1 ? "time" : "times"}`}
          </p>
        </div>
        {canManage && (
          <Button
            size="sm"
            variant="ghost"
            className="text-destructive shrink-0"
            onClick={() => router.delete(abilityRolePath(set.id))}
          >
            Delete set
          </Button>
        )}
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {set.grantCount > 0 && (
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
                  {canManage && (
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
                    className="hover:bg-muted/50 flex cursor-pointer items-center gap-3 px-3 py-2"
                  >
                    <Checkbox
                      checked={set.actionIds.includes(action.id)}
                      disabled={!canManage}
                      onCheckedChange={() => toggle(action.id)}
                    />
                    <code className="min-w-0 flex-1 truncate text-xs">{action.key}</code>
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
    </Card>
  )
}
