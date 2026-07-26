import { useEffect, useMemo, useState } from "react"
import { router } from "@inertiajs/react"

import type { AbilityActionOption, Principal } from "@/types/serializers"
import type { EnvironmentOption } from "@/pages/integrations/types"
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
import { RISK_VARIANT } from "@/pages/settings/components/permissions/risk"

export function GrantDialog({
  principal,
  actions,
  environments,
  onDismiss,
}: {
  principal: Principal | null
  actions: AbilityActionOption[]
  environments: EnvironmentOption[]
  onDismiss: () => void
}) {
  const [search, setSearch] = useState("")
  const [actionId, setActionId] = useState("")
  const [environmentIds, setEnvironmentIds] = useState<string[]>([])

  useEffect(() => {
    setSearch("")
    setActionId("")
    setEnvironmentIds([])
  }, [principal])

  const held = useMemo(
    () => new Set((principal?.grants ?? []).map((grant) => grant.actionId)),
    [principal],
  )

  const grouped = useMemo(() => {
    const matching = actions.filter(
      (action) => !held.has(action.id) && action.key.toLowerCase().includes(search.toLowerCase()),
    )
    const byGroup = new Map<string, AbilityActionOption[]>()
    matching.forEach((action) => {
      byGroup.set(action.group, [...(byGroup.get(action.group) ?? []), action])
    })
    return [...byGroup.entries()]
  }, [actions, held, search])

  function submit() {
    if (!principal || !actionId) return
    router.post(
      abilityGrantsPath(),
      {
        principal_type: principal.principalType,
        principal_id: principal.id,
        action_id: actionId,
        environment_ids: environmentIds,
      },
      { onFinish: onDismiss },
    )
  }

  function toggleEnvironment(id: string) {
    setEnvironmentIds((current) =>
      current.includes(id) ? current.filter((value) => value !== id) : [...current, id],
    )
  }

  return (
    <Dialog open={principal !== null} onOpenChange={(open) => { if (!open) onDismiss() }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Grant an ability to {principal?.name}</DialogTitle>
          <DialogDescription>
            Pick what it may do, then narrow it to environments. Leaving environments unticked means
            every environment.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-4">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="grant-search">Ability</Label>
            <Input
              id="grant-search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Search abilities…"
            />
            <div className="border-border max-h-64 overflow-y-auto rounded-lg border">
              {grouped.length === 0 ? (
                <p className="text-muted-foreground px-3 py-6 text-center text-sm">
                  {actions.length === held.size
                    ? "This principal already holds every ability."
                    : "No abilities match."}
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
                        onClick={() => setActionId(action.id)}
                        className={`flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm ${
                          actionId === action.id ? "bg-accent" : "hover:bg-muted/50"
                        }`}
                      >
                        <code className="min-w-0 truncate text-xs">{action.key}</code>
                        <Badge variant={RISK_VARIANT[action.riskLevel] ?? "secondary"} className="shrink-0">
                          {action.riskLevel}
                        </Badge>
                      </button>
                    ))}
                  </div>
                ))
              )}
            </div>
          </div>

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
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onDismiss}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={!actionId}>
            Grant ability
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
