import { IconAlertTriangle, IconCheck, IconExternalLink, IconMinus, IconX } from "@tabler/icons-react"
import { useState } from "react"

import { CodeAgentQuestion } from "@/components/code-agent-question"
import { CodeFixPauseCard } from "@/components/code-fix-pause"
import { useElapsed } from "@/hooks/use-elapsed"
import {
  type CodeFixCheck, type CodeFixLine, type CodeFixReview, type CodeFixWork, checkCouldNotRun, checkPassed, duration, earlierCount, failedLine, fileCounts, filesWord, latestTests,
  passedLine, paused, questionOpen, shownLines, stepsWord, stopped, wroteChange,
} from "@/lib/code-fix-work"

interface CodeFixWorkProps {
  work: CodeFixWork
  // The step is still running, so the newest line is where the agent is and the clock counts.
  running: boolean
  // Why whoever is looking cannot answer the agent's question, from the server, or null when they can.
  questionBlockedReason?: string | null
  // Why whoever is looking cannot continue or stop a change paused at its spending limit, or null when they can.
  pauseBlockedReason?: string | null
}

// What a coding agent writing a change is doing, under the step that runs it. While it works, its newest steps with the
// earlier ones a click away, how long it has been, the files it changed so far and any question it asked. Once it wrote
// the change, what it changed, the tests and checks that ran, what Halon's review found and the link. When it stopped,
// its last steps and why.
export function CodeFixWorkView({ work, running, questionBlockedReason = null, pauseBlockedReason = null }: CodeFixWorkProps) {
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
        {work.question && <CodeAgentQuestion question={work.question} />}
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
      {work.question && <CodeAgentQuestion question={work.question} blockedReason={running ? questionBlockedReason : null} />}
      {stopped(work) && work.reason && <p className="m-0 font-medium text-error [overflow-wrap:anywhere]">{work.reason}</p>}
      {paused(work) && work.pause && <CodeFixPauseCard pause={work.pause} blockedReason={pauseBlockedReason} />}
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

// The newest lines, keyed by their place among every line the agent wrote, so a line keeps its key as older ones drop.
function Lines({ lines, total, current }: { lines: CodeFixLine[]; total: number; current: boolean }) {
  const first = total - lines.length
  return (
    <ul className="m-0 flex list-none flex-col gap-0.5 p-0">
      {lines.map((line, index) => (
        <Line key={first + index} line={line} current={current && index === lines.length - 1} />
      ))}
    </ul>
  )
}

function Line({ line, current }: { line: CodeFixLine; current: boolean }) {
  return (
    <li className="flex min-w-0 items-start gap-2">
      <LineMark line={line} current={current} />
      <span className={`min-w-0 [overflow-wrap:anywhere] ${current ? "text-fg-primary" : "text-fg-secondary"}`}>{line.text}</span>
      {passedLine(line) && <span className="shrink-0 font-medium text-success">passed</span>}
      {failedLine(line) && <span className="shrink-0 font-medium text-error">failed</span>}
    </li>
  )
}

function LineMark({ line, current }: { line: CodeFixLine; current: boolean }) {
  if (current) {
    return <PulseMark />
  }
  if (failedLine(line)) {
    return <IconX aria-hidden className="mt-[3px] size-3.5 shrink-0 text-error" />
  }
  if (passedLine(line)) {
    return <IconCheck aria-hidden className="mt-[3px] size-3.5 shrink-0 text-success" />
  }
  return <span aria-hidden className="mt-[8px] ml-[5px] mr-[5px] size-1 shrink-0 rounded-full bg-fg-muted" />
}

function PulseMark() {
  return (
    <span aria-hidden className="relative mt-[6px] ml-[3px] mr-[3px] flex size-2 shrink-0">
      <span className="absolute inline-flex size-full rounded-full bg-stage-active opacity-60 motion-safe:animate-ping" />
      <span className="relative inline-flex size-2 rounded-full bg-stage-active" />
    </span>
  )
}

function WaitingLine({ words }: { words: string }) {
  return (
    <span className="flex items-start gap-2 text-fg-primary">
      <PulseMark />
      {words}
    </span>
  )
}

function ChangedFiles({ work }: { work: CodeFixWork }) {
  if (work.files.length === 0) {
    return null
  }

  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className="font-medium text-fg-primary">Changed {filesWord(work.files.length)}</span>
      <ul className="m-0 flex list-none flex-col gap-0.5 p-0">
        {work.files.map((file) => (
          <li key={file.path} className="flex min-w-0 items-baseline gap-2 font-mono text-[11.5px]">
            <span className="min-w-0 truncate text-fg-secondary" title={file.path}>{file.path}</span>
            <span className="shrink-0 text-fg-muted">{fileCounts(file)}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

function Tests({ work }: { work: CodeFixWork }) {
  const tests = latestTests(work)
  if (tests.length === 0) {
    return <span className="text-fg-muted">It ran no tests.</span>
  }

  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className="font-medium text-fg-primary">Tests</span>
      <ul className="m-0 flex list-none flex-col gap-0.5 p-0">
        {tests.map((test) => (
          <li key={test.command} className="flex min-w-0 items-start gap-2">
            {test.passed
              ? <IconCheck aria-hidden className="mt-[3px] size-3.5 shrink-0 text-success" />
              : <IconX aria-hidden className="mt-[3px] size-3.5 shrink-0 text-error" />}
            <code className="min-w-0 font-mono text-[11.5px] text-fg-secondary [overflow-wrap:anywhere]">{test.command}</code>
            <span className={`shrink-0 font-medium ${test.passed ? "text-success" : "text-error"}`}>{test.passed ? "passed" : "failed"}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

// What Halon's review made of the change before it opened, and what nobody could verify, which a reviewer checks first.
function Review({ review }: { review: CodeFixReview }) {
  if (!review.ran) {
    return (
      <span className="flex items-start gap-1.5 font-medium text-warning">
        <IconAlertTriangle aria-hidden className="mt-[3px] size-3.5 shrink-0" />
        {review.unverified[0]}
      </span>
    )
  }

  return (
    <div className="flex min-w-0 flex-col gap-1">
      <span className="flex items-start gap-1.5 font-medium text-fg-primary">
        <IconCheck aria-hidden className="mt-[3px] size-3.5 shrink-0 text-success" />
        {review.sentBack ? "Halon's review sent it back once, and the corrected change does what was asked" : "Halon's review: it does what was asked"}
      </span>
      {review.verified.length > 0 && <Notes title="Verified" notes={review.verified} />}
      {review.findings.length > 0 && <Notes title="Found in review" notes={review.findings} />}
      {review.unverified.length > 0 && <Notes title="Open questions" notes={review.unverified} warn />}
      {review.unreviewed.length > 0 && <Notes title="Not reviewed, since the change is too large to review whole" notes={review.unreviewed} warn />}
    </div>
  )
}

function Notes({ title, notes, warn = false }: { title: string; notes: string[]; warn?: boolean }) {
  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className={`font-medium ${warn ? "text-warning" : "text-fg-primary"}`}>{title}</span>
      <ul className="m-0 flex list-disc flex-col gap-0.5 pl-4">
        {notes.map((note) => (
          <li key={note} className="text-fg-secondary [overflow-wrap:anywhere]">{note}</li>
        ))}
      </ul>
    </div>
  )
}

function Checks({ work }: { work: CodeFixWork }) {
  if (work.checks.length === 0) {
    return null
  }

  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      <span className="font-medium text-fg-primary">Checks</span>
      <ul className="m-0 flex list-none flex-col gap-0.5 p-0">
        {work.checks.map((check) => (
          <CheckRow key={check.name} check={check} />
        ))}
      </ul>
    </div>
  )
}

function CheckRow({ check }: { check: CodeFixCheck }) {
  if (checkCouldNotRun(check)) {
    return (
      <li className="flex min-w-0 items-start gap-2">
        <IconMinus aria-hidden className="mt-[3px] size-3.5 shrink-0 text-fg-muted" />
        <span className="flex min-w-0 flex-col">
          <code className="font-mono text-[11.5px] text-fg-secondary [overflow-wrap:anywhere]">{check.name}</code>
          {check.reason && <span className="text-fg-muted">Could not run here, since {check.reason}.</span>}
        </span>
        <span className="shrink-0 font-medium text-fg-muted">could not run</span>
      </li>
    )
  }

  const passed = checkPassed(check)
  return (
    <li className="flex min-w-0 items-start gap-2">
      {passed
        ? <IconCheck aria-hidden className="mt-[3px] size-3.5 shrink-0 text-success" />
        : <IconX aria-hidden className="mt-[3px] size-3.5 shrink-0 text-error" />}
      <code className="min-w-0 font-mono text-[11.5px] text-fg-secondary [overflow-wrap:anywhere]">{check.name}</code>
      <span className={`shrink-0 font-medium ${passed ? "text-success" : "text-error"}`}>{check.status}</span>
    </li>
  )
}
