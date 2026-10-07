import { IconCheck, IconExternalLink, IconX } from "@tabler/icons-react"
import { useState } from "react"

import { useElapsed } from "@/hooks/use-elapsed"
import {
  type CodeFixLine, type CodeFixWork, duration, earlierCount, failedLine, fileCounts, filesWord, latestTests, opened, passedLine,
  shownLines, stepsWord, stopped,
} from "@/lib/code-fix-work"

interface CodeFixWorkProps {
  work: CodeFixWork
  // The step is still running, so the newest line is where the agent is and the clock counts.
  running: boolean
}

// What a coding agent writing a change is doing, under the step that runs it. While it works, its newest steps with the
// earlier ones a click away, how long it has been and the files it changed so far. Once it opened the pull request, what
// it changed, the tests it ran and the link. When it stopped, its last steps and why.
export function CodeFixWorkView({ work, running }: CodeFixWorkProps) {
  const elapsed = useElapsed(work.startedAt, work.finishedAt, running)
  const [ allLines, setAllLines ] = useState(false)

  function toggleLines() {
    setAllLines((shown) => !shown)
  }

  if (opened(work)) {
    return (
      <div className="flex min-w-0 flex-col gap-2 text-[12px] leading-5">
        <ChangedFiles work={work} />
        <Tests work={work} />
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

  return (
    <div className="flex min-w-0 flex-col gap-1.5 text-[12px] leading-5">
      {(earlier > 0 || allLines) && kept > 0 && (
        <button type="button" onClick={toggleLines} className="w-fit text-fg-muted underline decoration-border underline-offset-2 hover:text-fg-secondary">
          {earlierLabel(work, allLines, earlier)}
        </button>
      )}
      <Lines lines={shownLines(work, allLines)} total={work.total} current={working && work.live} />
      {working && !work.live && <WaitingLine words={kept === 0 ? "Getting the repository ready" : "The coding agent is writing the change"} />}
      {stopped(work) && work.reason && <p className="m-0 font-medium text-error [overflow-wrap:anywhere]">{work.reason}</p>}
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
