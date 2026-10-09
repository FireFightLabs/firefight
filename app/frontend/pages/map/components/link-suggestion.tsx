import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { confirmResourceMapLinkPath, dismissResourceMapLinkPath } from "@/lib/routes"
import { Clues } from "@/pages/map/components/clues"
import { howFound, RELATION_SENTENCES } from "@/pages/map/lib/labels"
import { MAP_VISIT } from "@/pages/map/lib/visit"
import type { ResourceMapLink, ResourceMapResource } from "@/types/serializers"

export function LinkSuggestion({ link, byId, canCurate }: { link: ResourceMapLink; byId: Map<string, ResourceMapResource>; canCurate: boolean }) {
  function confirm() {
    router.post(confirmResourceMapLinkPath(link.id), {}, MAP_VISIT)
  }

  function dismiss() {
    router.post(dismissResourceMapLinkPath(link.id), {}, MAP_VISIT)
  }

  return (
    <div className="flex flex-col gap-2 rounded-lg border border-dashed border-brand-border bg-brand-tint px-3 py-2.5 text-sm">
      <span>
        <b className="font-semibold">{byId.get(link.fromId)?.name}</b> {RELATION_SENTENCES[link.relation]}{" "}
        <b className="font-semibold">{byId.get(link.toId)?.name}</b>
      </span>
      <span className="text-xs text-muted-foreground">{howFound(link)}{link.note ? `: ${link.note}` : ""}</span>
      {link.clues.length > 0 && <Clues clues={link.clues} />}
      {canCurate && (
        <div className="flex gap-2">
          <Button type="button" size="sm" onClick={confirm}>
            Confirm link
          </Button>
          <Button type="button" size="sm" variant="outline" onClick={dismiss}>
            Dismiss
          </Button>
        </div>
      )}
    </div>
  )
}
