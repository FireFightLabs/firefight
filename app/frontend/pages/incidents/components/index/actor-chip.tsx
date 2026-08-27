import { IconKey, IconRobot, type Icon } from "@tabler/icons-react"

import type { ActorCompact } from "@/types/serializers"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { PRINCIPAL_KINDS } from "@/lib/generated/constants"

// A machine gets the same chip a person does, marked so nobody reads an
// agent's work as a colleague's.
const MACHINE_ICONS: Partial<Record<ActorCompact["kind"], Icon>> = {
  [PRINCIPAL_KINDS.AGENT]: IconRobot,
  [PRINCIPAL_KINDS.API_KEY]: IconKey,
}

export function ActorChip({ actor, fallback }: { actor?: ActorCompact; fallback: string }) {
  if (!actor) {
    return <span className="text-muted-foreground">{fallback}</span>
  }

  const MachineIcon = MACHINE_ICONS[actor.kind]

  return (
    <div className="flex items-center gap-2">
      <Avatar className="size-5">
        {actor.avatarUrl ? <AvatarImage src={actor.avatarUrl} alt={actor.name} /> : null}
        <AvatarFallback className="text-[10px] font-semibold bg-primary/20 text-primary">
          {MachineIcon ? <MachineIcon className="size-3" aria-label="Agent" /> : actor.initials}
        </AvatarFallback>
      </Avatar>
      <span className="font-medium truncate">{actor.name}</span>
    </div>
  )
}
