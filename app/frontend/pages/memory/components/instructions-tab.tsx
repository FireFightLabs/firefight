import { Link, router } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { memoryInstructionPath, settingsHandbookPath } from "@/lib/routes"
import { InstructionDialog } from "@/pages/memory/components/instruction-dialog"
import { InstructionRow } from "@/pages/memory/components/instruction-row"
import type { SubjectOption } from "@/pages/memory/types"
import type { ChatInstruction } from "@/types/serializers"

interface InstructionsTabProps {
  instructions: ChatInstruction[]
  subjects: SubjectOption[]
  canCurate: boolean
}

export function InstructionsTab({ instructions, subjects, canCurate }: InstructionsTabProps) {
  const [ editing, setEditing ] = useState<{ instruction: ChatInstruction | null } | null>(null)
  const [ removing, setRemoving ] = useState<ChatInstruction | null>(null)
  const taken = new Set(instructions.map((instruction) => instruction.scope))
  const scopes = subjects.filter((option) => !taken.has(option.value))

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
          How Halon should work for a team, a service or one resource. Where two disagree, the more specific one wins. What holds for the
          whole workspace goes in the <Link href={settingsHandbookPath()} className="text-link hover:underline">handbook</Link>.
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
            No instructions yet. Add some for a team or service that needs Halon to work a certain way.
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
