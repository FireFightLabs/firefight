import { IconCheck, IconLoader2 } from "@tabler/icons-react"

interface ToolRowProps {
  name: string
  answered: boolean
}

// What the agent reached for, in the order it happened.
export function ToolRow({ name, answered }: ToolRowProps) {
  const label = name.replace(/_/g, " ")

  return (
    <div className="flex items-center gap-2 py-0.5 text-[12.5px] text-ink-2">
      {answered ? (
        <IconCheck className="size-3.5 text-green" />
      ) : (
        <IconLoader2 className="size-3.5 animate-spin text-ink-3" />
      )}
      <span className="first-letter:uppercase">{label}</span>
    </div>
  )
}
