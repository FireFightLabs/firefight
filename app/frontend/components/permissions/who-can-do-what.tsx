import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconStack2, IconUser } from "@tabler/icons-react"

import type { AbilityRole, Principal } from "@/types/serializers"
import { abilityGrantsPath } from "@/lib/routes"
import { GRANT_KINDS, IMPLICIT_AUTHORITIES, PRINCIPAL_KINDS } from "@/lib/generated/constants"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"

// The default in one line, and a quick way to give one person a built-in pack. Granting goes through the same grant
// flow as the Permissions screen, which answers with a toast. Embedded on the Permissions screen and in onboarding.
export function WhoCanDoWhat({
  people,
  packs,
  canManage,
}: {
  people: Principal[]
  packs: AbilityRole[]
  canManage: boolean
}) {
  const [personId, setPersonId] = useState<string | null>(null)
  const [packId, setPackId] = useState<string | null>(null)
  const [giving, setGiving] = useState(false)

  const members = people.filter((person) => person.kind === PRINCIPAL_KINDS.USER && person.implicitAuthority === IMPLICIT_AUTHORITIES.MEMBER)
  const person = members.find((candidate) => candidate.id === personId) ?? null
  const held = new Set((person?.grants ?? []).filter((grant) => grant.kind === GRANT_KINDS.SET).map((grant) => grant.targetId))
  const offered = packs.filter((pack) => !held.has(pack.id))

  const personOptions: SearchableSelectOption[] = members.map((member) => ({
    value: member.id,
    label: member.name,
    icon: <IconUser className="text-muted-foreground size-4" />,
  }))
  const packOptions: SearchableSelectOption[] = offered.map((pack) => ({
    value: pack.id,
    label: pack.name,
    icon: <IconStack2 className="text-muted-foreground size-4" />,
  }))
  const descriptions = new Map(packs.map((pack) => [pack.id, pack.description]))
  const unavailable = unavailableReason(canManage, packs.length, members.length)

  function choosePerson(value: string | null) {
    setPersonId(value)
    setPackId(null)
  }

  function give() {
    if (!person || !packId) {
      return
    }
    setGiving(true)
    router.post(
      abilityGrantsPath(),
      { principal_kind: person.kind, principal_id: person.id, role_id: packId, environment_ids: [], expires_at: "" },
      { preserveScroll: true, onSuccess: clearPack, onFinish: stopGiving },
    )
  }

  function clearPack() {
    setPackId(null)
  }

  function stopGiving() {
    setGiving(false)
  }

  function renderPack(option: SearchableSelectOption) {
    return (
      <span className="flex min-w-0 flex-col">
        <span className="truncate">{option.label}</span>
        <span className="text-muted-foreground truncate text-xs">{descriptions.get(option.value)}</span>
      </span>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Who can do what</CardTitle>
        <CardDescription>Everyone reads every connected tool. Changes need a pack.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {unavailable ? (
          <p className="text-muted-foreground text-sm">{unavailable}</p>
        ) : (
          <>
            <div className="grid gap-3 md:grid-cols-[1fr_1fr_auto] md:items-end">
              <div className="flex min-w-0 flex-col gap-1.5">
                <Label>Person</Label>
                <SearchableSelect
                  value={personId}
                  onValueChange={choosePerson}
                  options={personOptions}
                  placeholder="Pick a person"
                  searchPlaceholder="Search people..."
                  emptyText="No one matches"
                />
              </div>
              <div className="flex min-w-0 flex-col gap-1.5">
                <Label>Pack</Label>
                <SearchableSelect
                  value={packId}
                  onValueChange={setPackId}
                  options={packOptions}
                  placeholder={person && offered.length === 0 ? "They hold every pack" : "Pick a pack"}
                  searchPlaceholder="Search packs..."
                  emptyText="No pack matches"
                  renderOption={renderPack}
                />
              </div>
              <Button onClick={give} disabled={!person || !packId || giving}>
                Give pack
              </Button>
            </div>
            <p className="text-muted-foreground text-xs">
              A pack given here reaches every environment. Narrow it to some, or set an expiry, from the person's grants
              under Permissions.
            </p>
          </>
        )}
      </CardContent>
    </Card>
  )
}

function unavailableReason(canManage: boolean, packCount: number, memberCount: number): string | null {
  if (!canManage) {
    return "Only an admin can give someone a pack."
  }
  if (packCount === 0) {
    return "Each connection brings its own packs. Connect a tool and they appear here."
  }
  if (memberCount === 0) {
    return "Everyone in this workspace is an admin, and admins can already do everything."
  }
  return null
}
