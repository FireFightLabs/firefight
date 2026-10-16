import { createConsumer } from "@rails/actioncable"
import { router } from "@inertiajs/react"
import { useEffect, useState } from "react"

import { INCIDENT_CHANNEL, INCIDENT_LIVE_PARTS } from "@/lib/generated/constants"
import type { IncidentPageProp } from "@/pages/incidents/lib/after-mutation"

type IncidentLivePart = (typeof INCIDENT_LIVE_PARTS)[keyof typeof INCIDENT_LIVE_PARTS]

interface LiveSignal {
  part: IncidentLivePart
}

// The props each part of the page is read from. The incident carries the runbooks, whose steps are action items, so
// an item changing reads the incident too. The run open over the page reads itself while it works.
const PROPS_OF: Record<IncidentLivePart, IncidentPageProp[]> = {
  [INCIDENT_LIVE_PARTS.INCIDENT]: [ "incident", "channelUrl", "subscribed", "attachableRunbooks", "investigationStart" ],
  [INCIDENT_LIVE_PARTS.TIMELINE]: [ "timelineEvents" ],
  [INCIDENT_LIVE_PARTS.ACTIONS]: [ "actions", "incident" ],
  [INCIDENT_LIVE_PARTS.POSTMORTEM]: [ "hasPostmortem", "postmortemStatus", "postmortemGenerationState" ],
  [INCIDENT_LIVE_PARTS.INVESTIGATION]: [ "investigationStart" ],
}

const EVERY_PART: IncidentLivePart[] = Object.values(INCIDENT_LIVE_PARTS)

// One change usually commits several rows (the incident, its timeline entry, a role), each saying so, so what arrives
// within this long is read in one reload.
const GATHER_MS = 300

// Keeps the incident page in step with changes made anywhere else: Slack, the API, MCP, Halon, a workflow or another
// tab. Only the props a change touched are read again, in place and without the progress bar, so a dialog or picker
// open on the page keeps what was typed. The toast for a change made here comes from its own response, never from this.
// Returns how many times the incident itself was read again, for panels that read their own answer from it.
export function useIncidentLive(incidentId: string): number {
  const [ incidentReads, setIncidentReads ] = useState(0)

  useEffect(() => {
    const waiting = new Set<IncidentLivePart>()
    let gathering: number | undefined

    function readAgain() {
      gathering = undefined
      const parts = [ ...waiting ]
      waiting.clear()
      const only = [ ...new Set(parts.flatMap((part) => PROPS_OF[part])) ]
      router.reload({ only, showProgress: false })
      if (only.includes("incident")) {
        setIncidentReads((reads) => reads + 1)
      }
    }

    function gather(parts: IncidentLivePart[]) {
      parts.forEach((part) => waiting.add(part))
      if (gathering === undefined) {
        gathering = window.setTimeout(readAgain, GATHER_MS)
      }
    }

    const consumer = createConsumer()
    const subscription = consumer.subscriptions.create(
      { channel: INCIDENT_CHANNEL, id: incidentId },
      {
        // Nothing sent before the socket listened is sent again, whether the page had just opened or the socket was away,
        // so the whole page is read each time it starts listening.
        connected() {
          gather(EVERY_PART)
        },
        received(signal: LiveSignal) {
          if (EVERY_PART.includes(signal.part)) {
            gather([ signal.part ])
          }
        },
      },
    )

    return () => {
      window.clearTimeout(gathering)
      subscription.unsubscribe()
      consumer.disconnect()
    }
  }, [ incidentId ])

  return incidentReads
}
