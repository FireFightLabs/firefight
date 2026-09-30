import { router } from "@inertiajs/react"
import { IconChevronDown, IconPlus } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { formatDate, formatDateTime } from "@/lib/formatters"
import { memoryInstructionPath } from "@/lib/routes"
import { InstructionDialog } from "@/pages/memory/components/instruction-dialog"
import { RowActions } from "@/pages/settings/components/row-actions"
import { type SubjectOption, WHOLE_WORKSPACE } from "@/pages/memory/types"
import type { ChatInstruction } from "@/types/serializers"

interface InstructionsTabProps {
  instructions: ChatInstruction[]
  subjects: SubjectOption[]
  canCurate: boolean
}

export function InstructionsTab({ instructions, subjects, canCurate }: InstructionsTabProps) {
  const [ editing, setEditing ] = useState<{ instruction: ChatInstruction | null } | null>(null)
  const [ removing, setRemoving ] = useState<ChatInstruction | null>(null)
  const taken = new Set(instructions.map((instruction) => instruction.scope ?? WHOLE_WORKSPACE))
  const scopes = [ { value: WHOLE_WORKSPACE, label: "Whole workspace" }, ...subjects ].filter((option) => !taken.has(option.value))

  function openAdd() {
    setEditing({ instruction: null })
  }

  function changeEditing(open: boolean) {
    if (!open) {
      setEditing(null)
    }
  }

  function remove() {
    if (removing) {
      router.delete(memoryInstructionPath(removing.id), { preserveScroll: true, onFinish: cancelRemove })
    }
  }

  function cancelRemove() {
    setRemoving(null)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Instructions for Halon</CardTitle>
        <CardDescription className="mt-1">
          How Halon should work, for the whole workspace, a team, a service or one resource. Where two disagree, the more specific one wins.
        </CardDescription>
        {canCurate && (
          <CardAction>
            <Button type="button" size="sm" onClick={openAdd}>
              <IconPlus className="size-4" />
              Add instructions
            </Button>
          </CardAction>
        )}
      </CardHeader>
      <CardContent className={instructions.length === 0 ? "" : "p-0"}>
        {instructions.length === 0 ? (
          <p className="pt-2 pb-8 text-center text-sm text-muted-foreground">
            No instructions yet. Add some for the whole workspace, or for a team or service that needs Halon to work a certain way.
          </p>
        ) : (
          <ul className="divide-y divide-border border-t border-border">
            {instructions.map((instruction) => (
              <InstructionRow key={instruction.id} instruction={instruction} canCurate={canCurate} onEdit={setEditing} onRemove={setRemoving} />
            ))}
          </ul>
        )}
      </CardContent>
      <InstructionDialog
        key={editing ? editing.instruction?.id ?? "new" : "closed"}
        open={editing !== null}
        onOpenChange={changeEditing}
        instruction={editing?.instruction ?? null}
        scopes={scopes}
      />
      <ConfirmDeleteDialog
        open={removing !== null}
        title={`Remove the instructions for ${removing?.label ?? "this place"}?`}
        description="Halon stops following them from its next chat or investigation. The wording is kept as history, and you can write new ones at any time."
        confirmLabel="Remove"
        onConfirm={remove}
        onCancel={cancelRemove}
      />
    </Card>
  )
}

interface InstructionRowProps {
  instruction: ChatInstruction
  canCurate: boolean
  onEdit: (editing: { instruction: ChatInstruction }) => void
  onRemove: (instruction: ChatInstruction) => void
}

function InstructionRow({ instruction, canCurate, onEdit, onRemove }: InstructionRowProps) {
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
