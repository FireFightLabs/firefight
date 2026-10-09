import { CheckRow } from "@/components/code-fix/check-row"
import type { CodeFixWork } from "@/lib/code-fix-work"

export function Checks({ work }: { work: CodeFixWork }) {
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
