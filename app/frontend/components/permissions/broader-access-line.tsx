import type { MemberAccessStanding } from "@/types/serializers"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { andList } from "@/lib/formatters"

type Through = MemberAccessStanding["through"][number]

// Abilities granted to a person one at a time have no set to name.
const ONE_BY_ONE = "abilities granted one by one"

export function peopleCount(count: number): string {
  return `${count} ${count === 1 ? "person" : "people"}`
}

// People a row leaves out who still reach the tool through other access, such as "2 people can through Changes
// everywhere". Their names show on hover, and where the page can open the set, its name opens it.
export function BroaderAccessLine({
  access,
  members,
  onOpenSet,
}: {
  access: Through
  members: { id: string; name: string }[]
  onOpenSet?: (setId: string) => void
}) {
  const names = andList(
    access.peopleIds.map((id) => members.find((member) => member.id === id)?.name).filter((name): name is string => Boolean(name)),
  )
  const setId = access.permissionSetId

  function openSet() {
    if (setId && onOpenSet) {
      onOpenSet(setId)
    }
  }

  return (
    <p className="text-muted-foreground text-xs">
      <Tooltip>
        <TooltipTrigger asChild>
          <button type="button" className="underline decoration-dotted underline-offset-2">
            {peopleCount(access.peopleIds.length)}
          </button>
        </TooltipTrigger>
        <TooltipContent side="top" className="max-w-56">{names}</TooltipContent>
      </Tooltip>{" "}
      can through{" "}
      {setId && onOpenSet ? (
        <button type="button" className="text-fg-primary inline text-left underline underline-offset-2" onClick={openSet}>
          {access.name}
        </button>
      ) : (
        access.name ?? ONE_BY_ONE
      )}
    </p>
  )
}
