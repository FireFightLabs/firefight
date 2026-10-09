import { IconCheck, IconX } from "@tabler/icons-react"

import { PulseMark } from "@/components/code-fix/pulse-mark"
import { type CodeFixLine, failedLine, passedLine } from "@/lib/code-fix-work"

export function LineMark({ line, current }: { line: CodeFixLine; current: boolean }) {
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
