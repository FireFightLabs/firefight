import { router } from "@inertiajs/react"

import type { Principal } from "@/types/serializers"
import { abilityGrantPath, withholdAbilityGrantsPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import { ActionLabel } from "@/pages/settings/components/permissions/action-label"

type DefaultAccess = Principal["defaultAccess"][number]

export function DefaultAccessRow({
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
