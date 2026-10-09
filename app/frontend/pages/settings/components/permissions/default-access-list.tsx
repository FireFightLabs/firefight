import type { Principal } from "@/types/serializers"
import { DefaultAccessRow } from "@/pages/settings/components/permissions/default-access-row"

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
