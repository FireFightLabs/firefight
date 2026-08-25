import { useEffect, useMemo, useState } from "react"
import { router } from "@inertiajs/react"

import type { AbilityActionOption, AbilityRole, ApprovalRule, EnvironmentOption, Principal } from "@/types/serializers"
import { abilityGrantsPath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { RequiresApprovalBadge } from "@/pages/settings/components/permissions/requires-approval-badge"
import { RISK_VARIANT } from "@/pages/settings/components/permissions/risk"
import { useGroupedActions } from "@/pages/settings/components/permissions/use-grouped-actions"
import { whenClosed } from "@/lib/handlers"

type Mode = "set" | "action"

export function GrantDialog({
  principal,
  actions,
  sets,
  environments,
  approvalRules,
  onDismiss,
}: {
  principal: Principal | null
  actions: AbilityActionOption[]
  sets: AbilityRole[]
  environments: EnvironmentOption[]
  approvalRules: ApprovalRule[]
  onDismiss: () => void
}) {
  const [mode, setMode] = useState<Mode>("set")
  const [search, setSearch] = useState("")
  const [targetId, setTargetId] = useState("")
  const [environmentIds, setEnvironmentIds] = useState<string[]>([])
  const [expiresAt, setExpiresAt] = useState("")

  useEffect(() => {
    setMode(sets.length > 0 ? "set" : "action")
    setSearch("")
    setTargetId("")
    setEnvironmentIds([])
    setExpiresAt("")
  }, [principal, sets.length])

  const held = useMemo(
    () => new Set((principal?.grants ?? []).map((grant) => grant.targetId)),
    [principal],
  )

  const availableSets = useMemo(
    () => sets.filter((set) => !held.has(set.id)),
    [sets, held],
  )

  const grouped = useGroupedActions(actions, search, held)

  function submit() {
    if (!principal || !targetId) {
      return
    }
    router.post(
      abilityGrantsPath(),
      {
        principal_type: principal.principalType,
        principal_id: principal.id,
        ...(mode === "set" ? { role_id: targetId } : { action_id: targetId }),
        environment_ids: environmentIds,
        expires_at: expiresAt,
      },
      { onFinish: onDismiss },
    )
  }

  function toggleEnvironment(id: string) {
    setEnvironmentIds((current) =>
      current.includes(id) ? current.filter((value) => value !== id) : [...current, id],
    )
  }

  function switchMode(next: Mode) {
    setMode(next)
    setTargetId("")
  }

  return (
    <Dialog open={principal !== null} onOpenChange={whenClosed(onDismiss)}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Grant to {principal?.name}</DialogTitle>
          <DialogDescription>
            Pick what it may do, then narrow it to environments. Leaving environments unticked means
            every environment.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-4">
          <div className="bg-muted flex rounded-lg p-1">
            {(["set", "action"] as Mode[]).map((option) => (
              <button
                key={option}
                type="button"
                onClick={() => switchMode(option)}
                className={`flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                  mode === option
                    ? "bg-background text-foreground shadow-sm"
                    : "text-muted-foreground hover:text-foreground"
                }`}
              >
                {option === "set" ? "Permission set" : "Single ability"}
              </button>
            ))}
          </div>

          {mode === "set" ? (
            <div className="border-border max-h-64 overflow-y-auto rounded-lg border">
              {availableSets.length === 0 ? (
                <p className="text-muted-foreground px-3 py-6 text-center text-sm">
                  {sets.length === 0
                    ? "No permission sets yet. Create one to grant several abilities at once."
                    : "This principal already holds every set."}
                </p>
              ) : (
                availableSets.map((set) => (
                  <button
                    key={set.id}
                    type="button"
                    onClick={() => setTargetId(set.id)}
                    className={`flex w-full items-center justify-between gap-3 px-3 py-2.5 text-left ${
                      targetId === set.id ? "bg-accent" : "hover:bg-muted/50"
                    }`}
                  >
                    <span className="min-w-0 truncate text-sm">{set.name}</span>
                    <span className="text-muted-foreground shrink-0 text-xs">
                      {set.actionIds.length} {set.actionIds.length === 1 ? "ability" : "abilities"}
                    </span>
                  </button>
                ))
              )}
            </div>
          ) : (
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="grant-search" className="sr-only">
                Ability
              </Label>
              <Input
                id="grant-search"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Search abilities…"
              />
              <div className="border-border max-h-64 overflow-y-auto rounded-lg border">
                {grouped.length === 0 ? (
                  <p className="text-muted-foreground px-3 py-6 text-center text-sm">
                    No abilities match.
                  </p>
                ) : (
                  grouped.map(([group, entries]) => (
                    <div key={group}>
                      <p className="bg-muted/50 text-muted-foreground px-3 py-1.5 text-xs font-medium">
                        {group}
                      </p>
                      {entries.map((action) => (
                        <button
                          key={action.id}
                          type="button"
                          onClick={() => setTargetId(action.id)}
                          className={`flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm ${
                            targetId === action.id ? "bg-accent" : "hover:bg-muted/50"
                          }`}
                        >
                          <code className="min-w-0 flex-1 truncate text-xs">{action.key}</code>
                          <RequiresApprovalBadge action={action} rules={approvalRules} />
                          <Badge
                            variant={RISK_VARIANT[action.riskLevel] ?? "secondary"}
                            className="shrink-0"
                          >
                            {action.riskLevel}
                          </Badge>
                        </button>
                      ))}
                    </div>
                  ))
                )}
              </div>
            </div>
          )}

          {environments.length > 0 && (
            <div className="flex flex-col gap-1.5">
              <Label>Environments</Label>
              <div className="flex flex-wrap gap-3">
                {environments.map((environment) => (
                  <label key={environment.id} className="flex items-center gap-2 text-sm">
                    <Checkbox
                      checked={environmentIds.includes(environment.id)}
                      onCheckedChange={() => toggleEnvironment(environment.id)}
                    />
                    {environment.name}
                  </label>
                ))}
              </div>
              <p className="text-muted-foreground text-xs">
                A scoped grant only matches calls that name one of these environments, and only where
                the connection has credentials wired for it.
              </p>
            </div>
          )}
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="grant-expires">Expires (optional)</Label>
            <Input
              id="grant-expires"
              type="date"
              value={expiresAt}
              onChange={(event) => setExpiresAt(event.target.value)}
            />
            <p className="text-muted-foreground text-xs">
              Leave empty to grant indefinitely. An expired grant stops working on its own and stays
              on this list, so you can see the access lapsed rather than wonder who removed it.
            </p>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onDismiss}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={!targetId}>
            Grant
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
