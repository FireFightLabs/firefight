import { createConsumer } from "@rails/actioncable"
import { router } from "@inertiajs/react"
import { type RefObject, useEffect } from "react"

import { WORKFLOW_CANVAS_PROPS, WORKFLOW_CHANNEL, WORKFLOW_LIVE_PARTS } from "@/lib/generated/constants"
import { CANVAS_VISIT } from "@/pages/halon/hooks/use-workflow-edits"

type WorkflowLivePart = (typeof WORKFLOW_LIVE_PARTS)[keyof typeof WORKFLOW_LIVE_PARTS]

interface LiveSignal {
  part: WorkflowLivePart
}

// The props each part of the page is read from. A run moving changes the list of runs, the newest run laid over the
// editor, the run open on the canvas and the run counts in the header.
const PROPS_OF: Record<WorkflowLivePart, string[]> = {
  [WORKFLOW_LIVE_PARTS.CANVAS]: CANVAS_VISIT.only,
  [WORKFLOW_LIVE_PARTS.RUNS]: [ WORKFLOW_CANVAS_PROPS.RUNS, WORKFLOW_CANVAS_PROPS.LAST_RUN, WORKFLOW_CANVAS_PROPS.RUN, WORKFLOW_CANVAS_PROPS.WORKFLOW ],
}

const EVERY_PART: WorkflowLivePart[] = Object.values(WORKFLOW_LIVE_PARTS)

// One change usually commits several rows (an edit and its draft, a step and its run), each saying so, so what arrives
// within this long is read in one reload.
const GATHER_MS = 300

// What a step still going does between the moves the server says, such as a watch reading or Halon calling a tool, shows
// within this long.
const RUN_REFRESH_MS = 5000

// Keeps the canvas in step with changes made anywhere else: another person's edit, Halon's suggestion, a publish, a run
// starting or moving on. The server says which part changed and only that part is read again, in place and without the
// progress bar, so nothing asks the server while nothing changes. While the run open on the canvas is going, its own
// details are read again every few seconds as well, one read at a time and never while the person's own visit waits,
// since a watch's reads and the tools Halon calls inside a step are not changes the page is told of.
export function useWorkflowLive(workflowId: string, runGoing: boolean, visitInFlight: RefObject<boolean>) {
  useEffect(() => {
    const waiting = new Set<WorkflowLivePart>()
    let gathering: number | undefined

    function readAgain() {
      gathering = undefined
      if (visitInFlight.current) {
        gathering = window.setTimeout(readAgain, GATHER_MS)
        return
      }
      const only = [ ...new Set([ ...waiting ].flatMap((part) => PROPS_OF[part])) ]
      waiting.clear()
      router.reload({ only, showProgress: false })
    }

    function gather(parts: WorkflowLivePart[]) {
      parts.forEach((part) => waiting.add(part))
      if (gathering === undefined) {
        gathering = window.setTimeout(readAgain, GATHER_MS)
      }
    }

    const consumer = createConsumer()
    const subscription = consumer.subscriptions.create(
      { channel: WORKFLOW_CHANNEL, id: workflowId },
      {
        // Nothing sent before the socket listened is sent again, whether the page had just opened or the socket was
        // away, so the whole page is read each time it starts listening.
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
  }, [ workflowId, visitInFlight ])

  useEffect(() => {
    if (!runGoing) {
      return
    }
    let timer: number | undefined
    let stopped = false

    function next() {
      if (!stopped) {
        timer = window.setTimeout(refresh, RUN_REFRESH_MS)
      }
    }

    function refresh() {
      if (visitInFlight.current) {
        next()
        return
      }
      router.reload({ only: [ WORKFLOW_CANVAS_PROPS.RUN ], showProgress: false, onFinish: next })
    }

    next()
    return () => {
      stopped = true
      window.clearTimeout(timer)
    }
  }, [ runGoing, visitInFlight ])
}
