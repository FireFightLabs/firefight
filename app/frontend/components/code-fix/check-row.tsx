import { IconCheck, IconMinus, IconX } from "@tabler/icons-react"

import { type CodeFixCheck, checkCouldNotRun, checkPassed } from "@/lib/code-fix-work"

export function CheckRow({ check }: { check: CodeFixCheck }) {
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
