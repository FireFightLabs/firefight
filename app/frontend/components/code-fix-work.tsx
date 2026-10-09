import { IconExternalLink } from "@tabler/icons-react"
import { useState } from "react"

import { CodeAgentQuestion } from "@/components/code-agent-question"
import { ChangedFiles } from "@/components/code-fix/changed-files"
import { Checks } from "@/components/code-fix/checks"
import { Lines } from "@/components/code-fix/lines"
import { Review } from "@/components/code-fix/review"
import { Tests } from "@/components/code-fix/tests"
import { WaitingLine } from "@/components/code-fix/waiting-line"
import { CodeFixPauseCard } from "@/components/code-fix-pause"
import { useElapsed } from "@/hooks/use-elapsed"
import {
  type CodeFixWork, duration, earlierCount, filesWord, paused, questionOpen, shownLines, stepsWord, stopped, wroteChange,
} from "@/lib/code-fix-work"

interface CodeFixWorkProps {
  work: CodeFixWork
  // The step is still running, so the newest line is where the agent is and the clock counts.
  running: boolean
  // Why whoever is looking cannot answer the agent's question, from the server, or null when they can.
  questionBlockedReason?: string | null
  // Why whoever is looking cannot change the answer to the agent's settled question, from the server, or null when they can.
  questionChangeBlockedReason?: string | null
  // Why whoever is looking cannot continue or stop a change paused at its spending limit, or null when they can.
  pauseBlockedReason?: string | null
  // Drawn before the server said who may decide, so the question and the pause offer nothing yet.
  readOnly?: boolean
  // The page props an answer or a decision changes, for a page that must not be visited whole.
  reloads?: string[]
}

// What a coding agent writing a change is doing, under the step that runs it. While it works, its newest steps with the
// earlier ones a click away, how long it has been, the files it changed so far and any question it asked. Once it wrote
// the change, what it changed, the tests and checks that ran, what Halon's review found and the link. When it stopped,
// its last steps and why.
export function CodeFixWorkView({
  work, running, questionBlockedReason = null, questionChangeBlockedReason = null, pauseBlockedReason = null, readOnly = false, reloads,
}: CodeFixWorkProps) {
  const elapsed = useElapsed(work.startedAt, work.finishedAt, running)
  const [ allLines, setAllLines ] = useState(false)

  function toggleLines() {
    setAllLines((shown) => !shown)
  }

  if (wroteChange(work)) {
    return (
      <div className="flex min-w-0 flex-col gap-2 text-[12px] leading-5">
        {work.review && <Review review={work.review} />}
        <ChangedFiles work={work} />
        <Tests work={work} />
        <Checks work={work} />
        {work.question && (
          <CodeAgentQuestion question={work.question} changeBlockedReason={questionChangeBlockedReason} readOnly={readOnly} reloads={reloads} />
        )}
        {work.pullRequest && (
          <a
            href={work.pullRequest}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex w-fit items-center gap-1 font-medium text-fg-primary underline decoration-border underline-offset-2 hover:decoration-fg-secondary"
          >
            Open the pull request
            <IconExternalLink className="size-3.5" />
          </a>
        )}
        <span className="flex flex-wrap items-center gap-x-2 text-fg-muted">
          <span>Took {duration(elapsed)} · {stepsWord(work.total)}</span>
          {work.lines.length > 0 && (
            <button type="button" onClick={toggleLines} className="underline decoration-border underline-offset-2 hover:text-fg-secondary">
              {allLines ? "Hide the steps" : "Show the steps"}
            </button>
          )}
        </span>
        {allLines && <Lines lines={work.lines} total={work.total} current={false} />}
      </div>
    )
  }

  const earlier = earlierCount(work, allLines)
  const kept = work.lines.length
  const working = running && !stopped(work)
  const waiting = working && work.question !== null && questionOpen(work.question)

  return (
    <div className="flex min-w-0 flex-col gap-1.5 text-[12px] leading-5">
      {(earlier > 0 || allLines) && kept > 0 && (
        <button type="button" onClick={toggleLines} className="w-fit text-fg-muted underline decoration-border underline-offset-2 hover:text-fg-secondary">
          {earlierLabel(work, allLines, earlier)}
        </button>
      )}
      <Lines lines={shownLines(work, allLines)} total={work.total} current={working && work.live && !waiting} />
      {working && !work.live && <WaitingLine words={kept === 0 ? "Getting the repository ready" : "The coding agent is writing the change"} />}
      {waiting && <WaitingLine words="Waiting for an answer" />}
      {work.question && (
        <CodeAgentQuestion
          question={work.question}
          blockedReason={running ? questionBlockedReason : null}
          changeBlockedReason={questionChangeBlockedReason}
          readOnly={readOnly}
          reloads={reloads}
        />
      )}
      {stopped(work) && work.reason && <p className="m-0 font-medium text-error [overflow-wrap:anywhere]">{work.reason}</p>}
      {paused(work) && work.pause && <CodeFixPauseCard pause={work.pause} blockedReason={pauseBlockedReason} readOnly={readOnly} reloads={reloads} />}
      <span className="text-fg-muted">
        {working ? `${duration(elapsed)} so far` : `Ran for ${duration(elapsed)}`}
        {work.changed.length > 0 && ` · ${filesWord(work.changed.length)} changed: ${changedList(work.changed)}`}
      </span>
    </div>
  )
}

function earlierLabel(work: CodeFixWork, all: boolean, earlier: number): string {
  if (!all) {
    return `Show ${stepsWord(earlier)} before these`
  }
  const lost = work.total - work.lines.length
  return lost > 0 ? `Hide the earlier steps (${stepsWord(lost)} before them were not kept)` : "Hide the earlier steps"
}

const CHANGED_NAMED = 3

function changedList(paths: string[]): string {
  const named = paths.slice(-CHANGED_NAMED).join(", ")
  const more = paths.length - CHANGED_NAMED
  return more > 0 ? `${named} and ${more} more` : named
}
