import { IconChevronDown } from "@tabler/icons-react"
import { useState } from "react"

import { formatDate, formatDateTime } from "@/lib/formatters"
import { RowActions } from "@/components/row-actions"
import type { ChatInstruction } from "@/types/serializers"

interface InstructionRowProps {
  instruction: ChatInstruction
  canCurate: boolean
  onEdit: (editing: { instruction: ChatInstruction }) => void
  onRemove: (instruction: ChatInstruction) => void
}

export function InstructionRow({ instruction, canCurate, onEdit, onRemove }: InstructionRowProps) {
  const [ showHistory, setShowHistory ] = useState(false)

  function edit() {
    onEdit({ instruction })
  }

  function remove() {
    onRemove(instruction)
  }

  function toggleHistory() {
    setShowHistory((shown) => !shown)
  }

  return (
    <li className="flex flex-col gap-2 px-6 py-4">
      <div className="flex items-start justify-between gap-3">
        <div className="flex flex-col gap-0.5">
          <span className="text-sm font-semibold">{instruction.label}</span>
          <span className="text-xs text-muted-foreground">
            {instruction.addedBy ? `${instruction.addedBy}, ` : ""}
            {formatDate(instruction.updatedAt)}
          </span>
        </div>
        {canCurate && <RowActions onEdit={edit} onDelete={remove} />}
      </div>
      <p className="max-w-3xl text-sm leading-relaxed whitespace-pre-wrap">{instruction.text}</p>
      {instruction.history.length > 0 && (
        <div className="flex flex-col gap-2">
          <button
            type="button"
            onClick={toggleHistory}
            aria-expanded={showHistory}
            className="flex w-fit items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
          >
            <IconChevronDown className={`size-3.5 transition-transform ${showHistory ? "rotate-180" : ""}`} />
            {showHistory ? "Hide" : "Show"} {instruction.history.length} earlier {instruction.history.length === 1 ? "wording" : "wordings"}
          </button>
          {showHistory && (
            <ol className="flex flex-col gap-2 border-l border-border pl-4">
              {instruction.history.map(([ id, writtenAt, writtenBy, text ]) => (
                <li key={id} className="flex flex-col gap-0.5">
                  <span className="text-xs text-muted-foreground">
                    {writtenBy ? `${writtenBy}, ` : ""}
                    {formatDateTime(writtenAt)}
                  </span>
                  <p className="text-sm whitespace-pre-wrap text-muted-foreground">{text}</p>
                </li>
              ))}
            </ol>
          )}
        </div>
      )}
    </li>
  )
}
