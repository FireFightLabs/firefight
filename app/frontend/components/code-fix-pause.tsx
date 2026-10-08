import { router } from "@inertiajs/react"
import { IconLoader2, IconPlayerPause } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import { type CodeFixPause, pauseContinuing, pauseOffered } from "@/lib/code-fix-work"
import { codeAgentPauseContinuePath, codeAgentPauseStopPath } from "@/lib/routes"

interface CodeFixPauseProps {
  pause: CodeFixPause
  // Why whoever is looking cannot decide, from the server, or null when they can.
  blockedReason: string | null
}

type Choice = "continue" | "stop"

// A code change that reached its spending limit before it finished, under the step that ran it. The person it runs as
// continues it, which gives it another budget of the same size and carries on where it stopped, or stops it, which
// deletes the work saved so far. Once decided, who decided and how.
export function CodeFixPauseCard({ pause, blockedReason }: CodeFixPauseProps) {
  const [ sending, setSending ] = useState<Choice | null>(null)

  function decide(choice: Choice) {
    setSending(choice)
    const path = choice === "continue" ? codeAgentPauseContinuePath(pause.id) : codeAgentPauseStopPath(pause.id)
    router.post(path, {}, { preserveScroll: true, onFinish: () => setSending(null) })
  }

  function continueChange() {
    decide("continue")
  }

  function stopChange() {
    decide("stop")
  }

  return (
    <div className="flex min-w-0 flex-col gap-1.5 rounded-md border border-border bg-surface-selected px-2.5 py-2">
      <span className="flex items-center gap-1.5 font-medium text-fg-primary">
        <IconPlayerPause aria-hidden className="size-3.5 shrink-0" />
        {pause.question}
      </span>
      {pause.savedBranch && <span className="text-fg-muted [overflow-wrap:anywhere]">Its work so far is saved on {pause.savedBranch}.</span>}
      {pauseOffered(pause) && blockedReason && <p className="m-0 text-fg-muted">{blockedReason}</p>}
      {pauseOffered(pause) && !blockedReason && (
        <div className="flex flex-wrap items-center gap-2">
          <Button type="button" size="sm" onClick={continueChange} disabled={sending !== null}>
            {sending === "continue" && <IconLoader2 className="motion-safe:animate-spin" />}
            Continue
          </Button>
          <Button type="button" size="sm" variant="outline" onClick={stopChange} disabled={sending !== null}>
            {sending === "stop" && <IconLoader2 className="motion-safe:animate-spin" />}
            Stop
          </Button>
        </div>
      )}
      {!pauseOffered(pause) && (
        <p className="m-0 text-fg-body">
          <span className="font-medium text-fg-primary">{pause.decidedBy ?? "Someone"}</span>
          {pauseContinuing(pause) ? " chose Continue." : " chose Stop, so the saved work was deleted."}
        </p>
      )}
    </div>
  )
}
