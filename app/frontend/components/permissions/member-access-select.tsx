import { useState } from "react"
import { router } from "@inertiajs/react"

import type { MemberAccessStanding } from "@/types/serializers"
import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { BroaderAccessLine, peopleCount } from "@/components/permissions/broader-access-line"
import { ChoosePeopleDialog } from "@/components/permissions/choose-people-dialog"
import { MEMBER_ACCESS } from "@/lib/generated/constants"
import { membersAbilityRolePath } from "@/lib/routes"

export type MemberAccessVerb = "read" | "change"

type Choice = MemberAccessStanding["choice"]

const CHOICE_LABELS: Record<Choice, string> = {
  [MEMBER_ACCESS.EVERYONE]: "Everyone",
  [MEMBER_ACCESS.NOBODY]: "Nobody",
  [MEMBER_ACCESS.CHOSEN]: "Choose people…",
}

// Reads open by default and changes closed, so each lists its default first.
const CHOICE_ORDER: Record<MemberAccessVerb, Choice[]> = {
  read: [MEMBER_ACCESS.EVERYONE, MEMBER_ACCESS.NOBODY, MEMBER_ACCESS.CHOSEN],
  change: [MEMBER_ACCESS.NOBODY, MEMBER_ACCESS.EVERYONE, MEMBER_ACCESS.CHOSEN],
}

// One dropdown of a connection's row. Everyone and Nobody save at once, and Choose people asks who first. The server
// answers each with a toast, and the page reloads with the grants as they stand.
export function MemberAccessSelect({
  verb,
  connectionName,
  standing,
  members,
  canManage,
  onOpenSet,
}: {
  verb: MemberAccessVerb
  connectionName: string
  standing: MemberAccessStanding
  members: { id: string; name: string }[]
  canManage: boolean
  onOpenSet?: (setId: string) => void
}) {
  const [choosing, setChoosing] = useState(false)
  const [saving, setSaving] = useState(false)
  const label = `Members can ${verb} ${connectionName}`
  const shown = standing.choice === MEMBER_ACCESS.CHOSEN ? peopleCount(standing.peopleIds.length) : CHOICE_LABELS[standing.choice]
  const holders = standing.choice === MEMBER_ACCESS.EVERYONE
    ? members.filter((member) => !standing.leftOutIds.includes(member.id)).map((member) => member.id)
    : standing.peopleIds
  const blockedReason = canManage ? standing.unavailableReason : "Only an admin can change who can do what."

  function save(choice: Choice, peopleIds: string[] = []) {
    setSaving(true)
    router.patch(
      membersAbilityRolePath(standing.packId),
      { choice, people_ids: peopleIds },
      { preserveScroll: true, onSuccess: stopChoosing, onFinish: stopSaving },
    )
  }

  function choose(value: string) {
    const choice = CHOICE_ORDER[verb].find((candidate) => candidate === value)
    if (choice === MEMBER_ACCESS.CHOSEN) {
      setChoosing(true)
      return
    }
    if (choice) {
      save(choice)
    }
  }

  function saveChosen(peopleIds: string[]) {
    save(MEMBER_ACCESS.CHOSEN, peopleIds)
  }

  function startChoosing() {
    setChoosing(true)
  }

  function stopChoosing() {
    setChoosing(false)
  }

  function stopSaving() {
    setSaving(false)
  }

  return (
    <div className="flex min-w-0 flex-col gap-1">
      <Blocked reason={blockedReason ?? undefined} side="top" className="block w-full">
        <Select value={standing.choice} onValueChange={choose} disabled={Boolean(blockedReason) || saving}>
          <SelectTrigger size="sm" className="w-full" aria-label={label}>
            <SelectValue>{shown}</SelectValue>
          </SelectTrigger>
          <SelectContent>
            {CHOICE_ORDER[verb].map((choice) => (
              <SelectItem key={choice} value={choice} disabled={choice === MEMBER_ACCESS.CHOSEN && members.length === 0}>
                {CHOICE_LABELS[choice]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Blocked>
      {standing.choice === MEMBER_ACCESS.EVERYONE && standing.leftOutIds.length > 0 && (
        <p className="text-muted-foreground text-xs">Except {peopleCount(standing.leftOutIds.length)}</p>
      )}
      {standing.through.map((access) => (
        <BroaderAccessLine key={access.permissionSetId ?? "one-by-one"} access={access} members={members} onOpenSet={onOpenSet} />
      ))}
      {standing.choice === MEMBER_ACCESS.CHOSEN && canManage && (
        <Button type="button" variant="link" size="sm" className="h-auto self-start p-0 text-xs" onClick={startChoosing}>
          Edit people
        </Button>
      )}
      {choosing && (
        <ChoosePeopleDialog
          title={`Who can ${verb} ${connectionName}?`}
          description={`Pick the members who can ask Halon to ${verb} ${connectionName}. Admins can always do everything.`}
          members={members}
          initial={holders}
          saving={saving}
          onSave={saveChosen}
          onDismiss={stopChoosing}
        />
      )}
    </div>
  )
}
