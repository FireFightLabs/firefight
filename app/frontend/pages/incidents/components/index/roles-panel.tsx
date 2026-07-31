import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import type { Incident } from "@/pages/incidents/types"

export function RolesPanel({ roles }: { roles: Incident["roles"] }) {
  if (roles.length === 0) return null

  return (
    <div className="rounded-lg border border-border bg-card px-4 py-3.5">
      <div className="mb-3 flex items-baseline gap-2">
        <h3 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-foreground/90">Roles</h3>
        <span className="text-[11px] tabular-nums text-muted-foreground/70">{roles.length}</span>
      </div>
      <ul className="flex flex-col gap-2.5">
        {roles.map((role) => (
          <li key={role.id} className="flex items-center justify-between gap-3">
            <span className="truncate text-xs text-muted-foreground">{role.name}</span>
            <div className="flex min-w-0 items-center gap-2">
              <Avatar className="size-5">
                {role.member.avatarUrl ? (
                  <AvatarImage src={role.member.avatarUrl} alt={role.member.name} />
                ) : null}
                <AvatarFallback className="bg-primary/20 text-[10px] font-semibold text-primary">
                  {role.member.initials}
                </AvatarFallback>
              </Avatar>
              <span className="truncate text-[13px] text-foreground">{role.member.name}</span>
            </div>
          </li>
        ))}
      </ul>
    </div>
  )
}
