import { useState } from "react"
import { router } from "@inertiajs/react"

import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { RATING_LABELS, isKeyOf } from "@/components/investigations/labels"
import { FINDING_OUTCOMES, type FindingOutcome } from "@/lib/generated/constants"
import { investigationRatingPath } from "@/lib/routes"

// Right, partly right or wrong, recorded the way Slack's buttons record it. The choice shows at once and goes back if
// the server refused it. A rating can be changed but not taken back, as in Slack.
export function RateAnswer({ investigationId, mine }: { investigationId: string; mine: string | null | undefined }) {
  const saved = mine && isKeyOf(RATING_LABELS, mine) ? mine : ""
  const [chosen, setChosen] = useState<string>(saved)

  function undo() {
    setChosen(saved)
  }

  function rate(outcome: string) {
    if (!outcome || outcome === chosen) {
      return
    }
    setChosen(outcome)
    router.post(investigationRatingPath(investigationId), { outcome }, { preserveScroll: true, onError: undo })
  }

  return (
    <ToggleGroup type="single" variant="outline" size="sm" value={chosen} onValueChange={rate} aria-label="Rate this answer">
      {FINDING_OUTCOMES.map((outcome: FindingOutcome) => (
        <ToggleGroupItem key={outcome} value={outcome} className="px-3">
          {RATING_LABELS[outcome]}
        </ToggleGroupItem>
      ))}
    </ToggleGroup>
  )
}
