import { router } from "@inertiajs/react"

import type { Principal } from "@/types/serializers"
import { abilityGrantPath, withholdAbilityGrantsPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import { ActionLabel } from "@/pages/settings/components/permissions/action-label"

type DefaultAccess = Principal["defaultAccess"][number]

// What a member holds without a grant, a connection's reads as one row. No access takes one away at once, and Restore
// removes that again.
export function DefaultAccessList({ principal, canManage }: { principal: Principal; canManage: boolean }) {
  if (principal.defaultAccess.length === 0) {
    return null
  }

  return (
    <div className="flex flex-col gap-2">
      <p className="text-xs font-medium">Held without a grant</p>
      <div className="border-border divide-border divide-y rounded-lg border">
        {principal.defaultAccess.map((access) => (
          <DefaultAccessRow key={access.targetId} principal={principal} access={access} canManage={canManage} />
        ))}
      </div>
    </div>
  )
}

function DefaultAccessRow({
  principal,
  access,
  canManage,
}: {
  principal: Principal
  access: DefaultAccess
  canManage: boolean
}) {
  const { grantId } = access

  function takeAway() {
    router.post(
      withholdAbilityGrantsPath(),
      {
        principal_kind: principal.kind,
        principal_id: principal.id,
        ...(access.kind === "set" ? { role_id: access.targetId } : { action_id: access.targetId }),
      },
      { preserveScroll: true },
    )
  }

  function restore() {
    if (grantId) {
      router.delete(abilityGrantPath(grantId), { preserveScroll: true })
    }
  }

  return (
    <div className="flex items-center justify-between gap-3 px-3 py-2.5">
      <ActionLabel actionKey={access.actionKey} title={access.title} description={access.note} />
      {canManage && (
        <Button variant="outline" size="sm" className="h-8 shrink-0" onClick={grantId ? restore : takeAway}>
          {grantId ? "Restore" : "No access"}
        </Button>
      )}
    </div>
  )
}
