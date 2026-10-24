import { createConsumer } from "@rails/actioncable"
import { router } from "@inertiajs/react"
import { type RefObject, useEffect, useRef } from "react"

import { LIVE_READ_HEADER, WORKFLOW_CANVAS_PROPS, WORKFLOW_CHANNEL, WORKFLOW_CHANNEL_CATCH_UP, WORKFLOW_CHANNEL_READ_AT_PARAM, WORKFLOW_LIVE_PARTS } from "@/lib/generated/constants"
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

// Marks each read as the page's own, so a change made here is toasted by its redirect alone, even when this read reaches
// the server while that redirect is still on its way.
const LIVE_READ = { headers: { [LIVE_READ_HEADER]: "true" }, showProgress: false }

// What a step still going does between the moves the server says, such as a watch reading or Halon calling a tool, shows
// within this long.
const RUN_REFRESH_MS = 5000

// Keeps the canvas in step with changes made anywhere else: another person's edit, Halon's suggestion, a publish, a run
// starting or moving on. The server says which part changed and only that part is read again, in place and without the
// progress bar, so nothing asks the server while nothing changes. While the run open on the canvas is going, its own
// details are read again every few seconds as well, since a watch's reads and the tools Halon calls inside a step are
// not changes the page is told of. Every read goes one at a time, never while the person's own visit waits, and what
// asks meanwhile is gathered into the next read, so an older answer never lands over a newer one. readAt is when the
// page's props were read, so the server tells it each time it starts listening only what changed since, rather than
// the page reading every part again just after it opened.
export function useWorkflowLive(workflowId: string, readAt: number, runGoing: boolean, visitInFlight: RefObject<boolean>) {
  const going = useRef(runGoing)

  useEffect(() => {
    going.current = runGoing
  }, [ runGoing ])

  useEffect(() => {
    const waiting = new Set<string>()
    let reading = false
    let gathering: number | undefined
    let stopped = false

    function readWaiting() {
      gathering = undefined
      if (stopped || waiting.size === 0) {
        return
      }
      if (reading || visitInFlight.current) {
        gathering = window.setTimeout(readWaiting, GATHER_MS)
        return
      }
      const only = [ ...waiting ]
      waiting.clear()
      reading = true
      router.reload({ ...LIVE_READ, only, onFinish: finishedReading })
    }

    function finishedReading() {
      reading = false
      if (waiting.size > 0 && gathering === undefined) {
        gathering = window.setTimeout(readWaiting, GATHER_MS)
      }
    }

    function ask(props: string[]) {
      props.forEach((prop) => waiting.add(prop))
      if (gathering === undefined) {
        gathering = window.setTimeout(readWaiting, GATHER_MS)
      }
    }

    function gather(part: WorkflowLivePart) {
      ask(PROPS_OF[part])
    }

    function refreshRun() {
      if (going.current) {
        ask([ WORKFLOW_CANVAS_PROPS.RUN ])
      }
    }

    const consumer = createConsumer()
    const subscription = consumer.subscriptions.create(
      { channel: WORKFLOW_CHANNEL, id: workflowId, [WORKFLOW_CHANNEL_READ_AT_PARAM]: readAt },
      {
        // Nothing sent before the socket listened is sent again, whether the page had just opened or the socket was
        // away, so once it listens it asks to catch up and the server says every part that changed since readAt, as it
        // says any change.
        connected() {
          subscription.perform(WORKFLOW_CHANNEL_CATCH_UP)
        },
        received(signal: LiveSignal) {
          if (EVERY_PART.includes(signal.part)) {
            gather(signal.part)
          }
        },
      },
    )
    const runTimer = window.setInterval(refreshRun, RUN_REFRESH_MS)

    return () => {
      stopped = true
      window.clearTimeout(gathering)
      window.clearInterval(runTimer)
      subscription.unsubscribe()
      consumer.disconnect()
    }
  }, [ workflowId, readAt, visitInFlight ])
}
