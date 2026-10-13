import { useState, type ComponentType } from "react"
import { IconChevronDown, IconPlus } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import type { WorkflowTemplate } from "@/lib/generated/constants"
import { isKeyOf } from "@/components/investigations/labels"
import { CheckLaterDialog } from "@/pages/halon/components/workflows/check-later-dialog"
import { ProbingScanDialog } from "@/pages/halon/components/workflows/probing-scan-dialog"
import type { WorkflowTemplateChoice } from "@/pages/halon/components/workflows/types"

interface TemplateDialogProps {
  template: WorkflowTemplateChoice
  open: boolean
  onClose: () => void
  timeZones: string[]
}

// Each template asks its own few questions.
const DIALOGS: Record<WorkflowTemplate, ComponentType<TemplateDialogProps>> = {
  check_later: CheckLaterDialog,
  probing_scan: ProbingScanDialog,
}

export function LibraryMenu({ templates, timeZones }: { templates: WorkflowTemplateChoice[]; timeZones: string[] }) {
  const [chosen, setChosen] = useState<WorkflowTemplateChoice | null>(null)

  function close() {
    setChosen(null)
  }

  const Chosen = chosen && isKeyOf(DIALOGS, chosen.key) ? DIALOGS[chosen.key] : null

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button size="sm">
            <IconPlus className="size-4" />
            New from the library
            <IconChevronDown className="size-3.5" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-80">
          {templates.map((template) => (
            <DropdownMenuItem key={template.key} onSelect={() => setChosen(template)} className="flex flex-col items-start gap-0.5">
              <span className="font-medium">{template.name}</span>
              <span className="text-xs text-muted-foreground">{template.description}</span>
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
      {chosen && Chosen && <Chosen key={chosen.key} template={chosen} open onClose={close} timeZones={timeZones} />}
    </>
  )
}
