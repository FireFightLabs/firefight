import { WhatChanged } from "@/components/what-changed"
import { incidentChangesPath } from "@/lib/routes"

// What changed on the resources the incident's catalog entries run, from a little before it started until now, read
// when the page opens. Shown to those who may read the map, since that is where it comes from.
export function ChangesPanel({ incidentId, canReadMap }: { incidentId: string; canReadMap: boolean }) {
  if (!canReadMap) {
    return null
  }

  function pathFor(reads: number): string {
    return reads > 0 ? incidentChangesPath(incidentId, { live: reads }) : incidentChangesPath(incidentId)
  }

  return (
    <div className="rounded-xl border border-border bg-card px-5 py-4">
      <h3 className="mb-3 text-[12px] font-semibold uppercase tracking-[0.10em] text-fg-primary">What changed</h3>
      <WhatChanged pathFor={pathFor} quiet="Nothing Firefight holds changed on what this incident touches since a little before it started." />
    </div>
  )
}
