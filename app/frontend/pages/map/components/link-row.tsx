import { useState } from "react"
import { router } from "@inertiajs/react"

import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { RESOURCE_MAP_ORIGIN } from "@/lib/generated/constants"
import { confirmResourceMapLinkPath, dismissResourceMapLinkPath, resourceMapLinkPath } from "@/lib/routes"
import { Clues } from "@/pages/map/components/clues"
import { howFound, RELATION_SENTENCES } from "@/pages/map/lib/labels"
import { MAP_VISIT } from "@/pages/map/lib/visit"
import type { ResourceMapLink, ResourceMapResource } from "@/types/serializers"

interface LinkRowProps {
  link: ResourceMapLink
  byId: Map<string, ResourceMapResource>
  focusId: string
  canCurate: boolean
  onPick: (resourceId: string) => void
}

export function LinkRow({ link, byId, focusId, canCurate, onPick }: LinkRowProps) {
  const from = byId.get(link.fromId)
  const to = byId.get(link.toId)
  const other = link.fromId === focusId ? to : from
  // A suggestion shows what it rests on, and so does a match from a setting, since its clue names the setting.
  const showsClues = (link.unconfirmed || link.origin === RESOURCE_MAP_ORIGIN.MATCHED) && link.clues.length > 0
  // A provider's link cannot be removed by hand, so Remove link stays and says why.
  const [ removing, setRemoving ] = useState(false)

  function confirm() {
    router.post(confirmResourceMapLinkPath(link.id), {}, MAP_VISIT)
  }

  function dismiss() {
    router.post(dismissResourceMapLinkPath(link.id), {}, MAP_VISIT)
  }

  function askRemove() {
    setRemoving(true)
  }

  function cancelRemove() {
    setRemoving(false)
  }

  function remove() {
    router.delete(resourceMapLinkPath(link.id), { ...MAP_VISIT, onFinish: cancelRemove })
  }

  function pickOther() {
    if (other) {
      onPick(other.id)
    }
  }

  return (
    <div className={`flex flex-col gap-1.5 rounded-lg border px-3 py-2.5 text-sm ${link.unconfirmed ? "border-dashed border-brand-border bg-brand-tint" : "border-border bg-surface-card"}`}>
      <span>
        <b className="font-semibold">{from?.name}</b> {RELATION_SENTENCES[link.relation]}{" "}
        <button type="button" onClick={pickOther} className="font-semibold hover:underline">
          {to?.name}
        </button>
      </span>
      <span className="text-xs text-muted-foreground">{howFound(link)}{link.note ? `: ${link.note}` : ""}</span>
      {showsClues && <Clues clues={link.clues} />}
      {canCurate && link.unconfirmed && (
        <div className="flex gap-2 pt-1">
          <Button type="button" size="sm" onClick={confirm}>
            Confirm link
          </Button>
          <Button type="button" size="sm" variant="outline" onClick={dismiss}>
            Dismiss
          </Button>
        </div>
      )}
      {canCurate && !link.unconfirmed && (
        <Blocked reason={link.removalBlockedReason}>
          <Button type="button" size="sm" variant="ghost" className="h-7 w-fit px-2 text-xs text-muted-foreground" disabled={Boolean(link.removalBlockedReason)} onClick={askRemove}>
            Remove link
          </Button>
        </Blocked>
      )}
      <ConfirmDeleteDialog
        open={removing}
        title="Remove this link?"
        description={`The map and Halon stop treating ${from?.name ?? "it"} as depending on ${to?.name ?? "the other resource"}. You can add it again at any time.`}
        confirmLabel="Remove link"
        onConfirm={remove}
        onCancel={cancelRemove}
      />
    </div>
  )
}
