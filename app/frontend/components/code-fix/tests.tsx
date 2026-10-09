import { IconCheck, IconX } from "@tabler/icons-react"

import { type CodeFixWork, latestTests } from "@/lib/code-fix-work"

export function Tests({ work }: { work: CodeFixWork }) {
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
