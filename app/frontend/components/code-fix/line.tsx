import { LineMark } from "@/components/code-fix/line-mark"
import { type CodeFixLine, failedLine, passedLine } from "@/lib/code-fix-work"

export function Line({ line, current }: { line: CodeFixLine; current: boolean }) {
  return (
    <li className="flex min-w-0 items-start gap-2">
      <LineMark line={line} current={current} />
      <span className={`min-w-0 [overflow-wrap:anywhere] ${current ? "text-fg-primary" : "text-fg-secondary"}`}>{line.text}</span>
      {passedLine(line) && <span className="shrink-0 font-medium text-success">passed</span>}
      {failedLine(line) && <span className="shrink-0 font-medium text-error">failed</span>}
    </li>
  )
}
