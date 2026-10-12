import type { ReactNode } from "react"

import type { MemberAccess } from "@/types/serializers"
import { MemberAccessSelect } from "@/components/permissions/member-access-select"

// One row per connection with what members can read and change through it. Shown in setup and on the Permissions screen,
// both reading the same grants, so a choice made in one is what the other shows.
export function MemberAccessTable({
  access,
  canManage,
  empty,
}: {
  access: MemberAccess
  canManage: boolean
  empty: ReactNode
}) {
  if (access.connections.length === 0) {
    return <div className="text-muted-foreground text-sm">{empty}</div>
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="border-border divide-border divide-y rounded-lg border">
        <div className="text-muted-foreground hidden grid-cols-[minmax(0,1fr)_11rem_11rem] gap-4 px-3 py-2 text-xs font-medium md:grid">
          <span>Tool</span>
          <span>Members can read</span>
          <span>Members can change</span>
        </div>
        {access.connections.map((connection) => (
          <div
            key={connection.id}
            className="grid grid-cols-2 items-start gap-x-4 gap-y-2 px-3 py-3 md:grid-cols-[minmax(0,1fr)_11rem_11rem]"
          >
            <p className="col-span-2 min-w-0 truncate pt-1.5 text-sm font-medium md:col-span-1">{connection.name}</p>
            <div className="flex min-w-0 flex-col gap-1">
              <span className="text-muted-foreground text-xs md:hidden">Members can read</span>
              <MemberAccessSelect
                verb="read"
                connectionName={connection.name}
                standing={connection.read}
                members={access.members}
                canManage={canManage}
              />
            </div>
            <div className="flex min-w-0 flex-col gap-1">
              <span className="text-muted-foreground text-xs md:hidden">Members can change</span>
              <MemberAccessSelect
                verb="change"
                connectionName={connection.name}
                standing={connection.change}
                members={access.members}
                canManage={canManage}
              />
            </div>
          </div>
        ))}
      </div>
      <p className="text-muted-foreground text-xs">Changes always follow your approval rules.</p>
    </div>
  )
}
