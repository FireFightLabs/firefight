import { CODE_FIX_LINE_RESULTS, CODE_FIX_OUTCOMES } from "@/lib/generated/constants"
import type { InvestigationRemediationStep } from "@/types/serializers"

// What a coding agent writing a change has done so far, the same shape on a chat step and on a fix step.
export type CodeFixWork = NonNullable<InvestigationRemediationStep["progress"]>
export type CodeFixLine = CodeFixWork["lines"][number]
export type CodeFixTest = CodeFixWork["tests"][number]
export type CodeFixFile = CodeFixWork["files"][number]

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
