import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import type { Incident } from "@/pages/incidents/types"
import { InlineSelect, type InlineChoice } from "@/pages/incidents/components/index/inline-select"
import { assignIncidentRolePath } from "@/lib/routes"

// Clearing a role is picking nobody, so the picker carries an entry for it
// rather than hiding the option behind a separate control.
const UNASSIGNED = ""

function Holder({ member }: { member: Incident["roles"][number]["member"] }) {
  if (!member) {
    return <span className="text-[13px] text-muted-foreground/70">Unassigned</span>
  }

  return (
    <div className="flex min-w-0 items-center gap-2">
      <Avatar className="size-5">
        {member.avatarUrl ? <AvatarImage src={member.avatarUrl} alt={member.name} /> : null}
        <AvatarFallback className="bg-primary/20 text-[10px] font-semibold text-primary">
          {member.initials}
        </AvatarFallback>
      </Avatar>
      <span className="truncate text-[13px] text-foreground">{member.name}</span>
    </div>
  )
}

export function RolesPanel({
  roles,
  incidentId,
  candidates,
  blockedReason,
}: {
  roles: Incident["roles"]
  incidentId: string
  candidates: InlineChoice[]
  blockedReason?: string | null
}) {
  if (roles.length === 0) {
    return null
  }

  const choices: InlineChoice[] = [ { value: UNASSIGNED, label: "Unassigned" }, ...candidates ]

  return (
    <div className="rounded-xl border border-border bg-card px-5 py-4">
      <h3 className="mb-3 text-[12px] font-semibold uppercase tracking-[0.10em] text-foreground">Roles</h3>
      <ul className="flex flex-col gap-2.5">
        {roles.map((role) => (
          <li key={role.id} className="flex items-center justify-between gap-3">
            <span className="truncate text-xs text-muted-foreground">{role.name}</span>
            <InlineSelect
              trigger={<Holder member={role.member} />}
              choices={choices}
              selected={role.memberId ?? UNASSIGNED}
              path={assignIncidentRolePath(incidentId)}
              payload={(value) => ({ role: role.slug, member_id: value })}
              blockedReason={blockedReason}
              align="end"
            />
          </li>
        ))}
      </ul>
    </div>
  )
}
