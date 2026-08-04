import type { ActorCompact } from "@/types/serializers"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"

export function PersonChip({
  person,
  fallback,
}: {
  person?: ActorCompact
  fallback: string
}) {
  if (!person) {
    return <span className="text-muted-foreground">{fallback}</span>
  }

  return (
    <div className="flex items-center gap-2">
      <Avatar className="size-5">
        {person.avatarUrl ? <AvatarImage src={person.avatarUrl} alt={person.name} /> : null}
        <AvatarFallback className="text-[10px] font-semibold bg-primary/20 text-primary">
          {person.initials}
        </AvatarFallback>
      </Avatar>
      <span className="font-medium truncate">{person.name}</span>
    </div>
  )
}
