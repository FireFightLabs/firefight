import {
  CODE_AGENT_QUESTION_STATUSES, CODE_CHECK_STATUSES, CODE_FIX_LINE_RESULTS, CODE_FIX_OUTCOMES, CODE_FIX_PAUSE_STATUSES,
} from "@/lib/generated/constants"
import type { InvestigationRemediationStep } from "@/types/serializers"

// What a coding agent writing a change has done so far, the same shape on a chat step and on a fix step.
export type CodeFixWork = NonNullable<InvestigationRemediationStep["progress"]>
export type CodeFixLine = CodeFixWork["lines"][number]
export type CodeFixTest = CodeFixWork["tests"][number]
export type CodeFixFile = CodeFixWork["files"][number]
export type CodeFixQuestion = NonNullable<CodeFixWork["question"]>
export type CodeFixQuestionOption = CodeFixQuestion["options"][number]
export type CodeFixReview = NonNullable<CodeFixWork["review"]>
export type CodeFixCheck = CodeFixWork["checks"][number]

// The newest lines show while it works, and the earlier ones open on request.
export const LINES_SHOWN = 5

export function shownLines(work: CodeFixWork, all: boolean): CodeFixLine[] {
  return all ? work.lines : work.lines.slice(-LINES_SHOWN)
}

// Lines before the ones shown, kept or not.
export function earlierCount(work: CodeFixWork, all: boolean): number {
  return work.total - shownLines(work, all).length
}

export function failedLine(line: CodeFixLine): boolean {
  return line.result === CODE_FIX_LINE_RESULTS.FAILED
}

export function passedLine(line: CodeFixLine): boolean {
  return line.result === CODE_FIX_LINE_RESULTS.PASSED
}

// Opened a pull request, or added a commit to a branch that already had one.
export function wroteChange(work: CodeFixWork): boolean {
  return work.outcome === CODE_FIX_OUTCOMES.OPENED || work.outcome === CODE_FIX_OUTCOMES.PUSHED
}

export type CodeFixPause = NonNullable<CodeFixWork["pause"]>

// Reached its spending limit and waits for the person to continue or stop it.
export function paused(work: CodeFixWork): boolean {
  return work.outcome === CODE_FIX_OUTCOMES.PAUSED
}

export function pauseOffered(pause: CodeFixPause): boolean {
  return pause.status === CODE_FIX_PAUSE_STATUSES.OFFERED
}

export function pauseContinuing(pause: CodeFixPause): boolean {
  return pause.status === CODE_FIX_PAUSE_STATUSES.CONTINUING
}

export function stopped(work: CodeFixWork): boolean {
  return work.outcome === CODE_FIX_OUTCOMES.FAILED
}

// Each test command once, with how it went the last time it ran.
export function latestTests(work: CodeFixWork): CodeFixTest[] {
  const byCommand = new Map<string, CodeFixTest>()
  work.tests.forEach((test) => {
    byCommand.delete(test.command)
    byCommand.set(test.command, test)
  })
  return [ ...byCommand.values() ]
}

// Lines added and removed, or binary when git could not count them.
export function fileCounts(file: CodeFixFile): string {
  if (file.added === null || file.removed === null) {
    return "binary"
  }
  return `+${file.added} -${file.removed}`
}

export function duration(seconds: number): string {
  if (seconds < 60) {
    return `${seconds}s`
  }
  const minutes = Math.floor(seconds / 60)
  return `${minutes}m ${seconds % 60}s`
}

export function stepsWord(count: number): string {
  return count === 1 ? "1 step" : `${count} steps`
}

export function filesWord(count: number): string {
  return count === 1 ? "1 file" : `${count} files`
}

// The agent asked and is waiting, so the person can answer it here.
export function questionOpen(question: CodeFixQuestion): boolean {
  return question.status === CODE_AGENT_QUESTION_STATUSES.OPEN
}

export function questionAnswered(question: CodeFixQuestion): boolean {
  return question.status === CODE_AGENT_QUESTION_STATUSES.ANSWERED
}

// Nobody answered in time, so the change went with the agent's recommendation.
export function questionDefaulted(question: CodeFixQuestion): boolean {
  return question.status === CODE_AGENT_QUESTION_STATUSES.DEFAULTED
}

// The option the change carries on with now, by its place, or null for an answer in someone's own words.
export function currentChoice(question: CodeFixQuestion): number | null {
  return question.changedAt ? question.changedChosen : question.chosen
}

// The same question as two reports of it, the newer one. The page reads it from the database while the socket carries
// what the change last reported, so either can be ahead.
export function newerQuestion(first: CodeFixQuestion | null, second: CodeFixQuestion | null): CodeFixQuestion | null {
  if (!first || !second || first.id !== second.id) {
    return first ?? second
  }
  return Date.parse(second.updatedAt ?? "") > Date.parse(first.updatedAt ?? "") ? second : first
}

// The work the socket reported, with whichever of its question and the saved one is newer.
export function withNewerQuestion(live: CodeFixWork | null, saved: CodeFixWork | null): CodeFixWork | null {
  if (!live || !saved) {
    return live ?? saved
  }
  return { ...live, question: newerQuestion(live.question, saved.question) }
}

export function questionExpired(question: CodeFixQuestion): boolean {
  return question.status === CODE_AGENT_QUESTION_STATUSES.EXPIRED
}

export function checkPassed(check: CodeFixCheck): boolean {
  return check.status === CODE_CHECK_STATUSES.PASSED
}

// Stopped by something missing where the checks run, such as a database, so it says nothing about the change.
export function checkCouldNotRun(check: CodeFixCheck): boolean {
  return check.status === CODE_CHECK_STATUSES.COULD_NOT_RUN
}

// Answering a question or deciding a pause redirects back. A page whose list loads by the page names the props that
// change, so the redirect never asks for the list again. Elsewhere it is an ordinary visit.
export function decisionVisit(reloads: string[] | undefined) {
  return reloads ? { preserveScroll: true, preserveState: true, only: reloads } : { preserveScroll: true }
}
