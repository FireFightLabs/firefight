import { useEffect, useState, type ChangeEvent, type FormEvent } from "react"
import type { Errors } from "@inertiajs/core"
import { router } from "@inertiajs/react"

import { Blocked } from "@/components/blocked-tooltip"
import { FormErrors } from "@/components/form-errors"
import { MarkdownEditor } from "@/components/markdown-editor"
import { SearchableMultiSelect, type SearchableMultiSelectOption } from "@/components/searchable-multi-select"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { SKILL_LIMITS, SKILL_PAGE_PROPS } from "@/lib/generated/constants"
import { omitErrors } from "@/lib/form-errors"
import { whenClosed } from "@/lib/handlers"
import { acceptHalonSkillProposalPath, halonSkillPath, halonSkillsPath } from "@/lib/routes"
import type { HalonSkillToolChoice } from "@/types/serializers"
import { SkillToolOption } from "@/pages/halon/components/skills/skill-tool-option"
import type { SkillDialogState } from "@/pages/halon/components/skills/types"

interface Draft {
  name: string
  usedWhen: string
  tools: string[]
  steps: string
  reason: string
}

const FIELDS_WITH_OWN_ERRORS = [ "name", "when", "tools", "steps", "reason" ]

function messageOf(errors: Errors, field: string): string | undefined {
  const message = errors[field]
  return Array.isArray(message) ? message[0] : message
}

function draftFor(state: SkillDialogState): Draft {
  if (state?.mode === "edit") {
    return { name: state.skill.name, usedWhen: state.skill.usedWhen, tools: state.skill.tools, steps: state.skill.steps, reason: "" }
  }
  if (state?.mode === "proposal") {
    const proposed = state.proposal.proposed
    return { name: state.proposal.name, usedWhen: proposed.usedWhen, tools: proposed.tools, steps: proposed.steps, reason: "" }
  }
  return { name: "", usedWhen: "", tools: [], steps: "", reason: "" }
}

function titleFor(state: SkillDialogState): string {
  if (state?.mode === "edit") {
    return `Edit ${state.skill.name}`
  }
  if (state?.mode === "proposal") {
    return `Edit Halon's proposed ${state.proposal.name}`
  }
  return "New skill"
}

function toolOption(choice: HalonSkillToolChoice): SearchableMultiSelectOption {
  return { value: choice.name, label: `${choice.name} ${choice.group}` }
}

function loadToolChoices() {
  router.reload({ only: [ SKILL_PAGE_PROPS.TOOL_CHOICES ] })
}

// Owns writing a new skill, editing one and editing Halon's proposal before accepting it, as every settings dialog
// owns both create and edit. The tools load when it first opens, since they are read from every connection.
export function SkillDialog({
  state,
  toolChoices,
  onClose,
}: {
  state: SkillDialogState
  toolChoices: HalonSkillToolChoice[] | undefined
  onClose: () => void
}) {
  const [ draft, setDraft ] = useState<Draft>(() => draftFor(state))
  const [ errors, setErrors ] = useState<Errors>({})
  const [ processing, setProcessing ] = useState(false)
  const editing = state?.mode === "edit" ? state.skill : null
  const proposal = state?.mode === "proposal" ? state.proposal : null
  const identity = `${state?.mode ?? "closed"}:${editing?.id ?? proposal?.id ?? ""}`
  const [ lastIdentity, setLastIdentity ] = useState<string | null>(null)
  if (state && identity !== lastIdentity) {
    setLastIdentity(identity)
    setDraft(draftFor(state))
    setErrors({})
  }

  const open = Boolean(state)
  const toolsLoaded = toolChoices !== undefined
  useEffect(() => {
    if (open && !toolsLoaded) {
      loadToolChoices()
    }
  }, [ open, toolsLoaded ])

  const choices = toolChoices ?? []
  const options = choices.map(toolOption)
  const renameBlocked = editing?.renameBlockedReason ?? proposal?.renameBlockedReason
  const copyOf = editing?.copyOf ?? proposal?.copyOf
  const fieldId = (field: string) => `skill-${field}-${editing?.id ?? proposal?.id ?? "new"}`

  function change<Key extends keyof Draft>(key: Key, value: Draft[Key]) {
    setDraft((current) => ({ ...current, [key]: value }))
  }

  function writeName(event: ChangeEvent<HTMLInputElement>) {
    change("name", event.target.value)
  }

  function writeWhen(event: ChangeEvent<HTMLTextAreaElement>) {
    change("usedWhen", event.target.value)
  }

  function writeReason(event: ChangeEvent<HTMLInputElement>) {
    change("reason", event.target.value)
  }

  function pickTools(tools: string[]) {
    change("tools", tools)
  }

  function writeSteps(steps: string) {
    change("steps", steps)
  }

  function showErrors(received: Errors) {
    setErrors(received)
  }

  function doneSending() {
    setProcessing(false)
  }

  function renderToolBadge(option: SearchableMultiSelectOption) {
    return <span className="font-mono text-xs">{option.value}</span>
  }

  function renderToolOption(option: SearchableMultiSelectOption) {
    return <SkillToolOption choice={choices.find((choice) => choice.name === option.value)} />
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setProcessing(true)
    const params = { name: draft.name, when: draft.usedWhen, tools: draft.tools, steps: draft.steps, reason: draft.reason }
    const options = { preserveScroll: true, onSuccess: onClose, onError: showErrors, onFinish: doneSending }

    if (editing) {
      router.patch(halonSkillPath(editing.id), {
        ...params, seen_version_id: editing.versionId, references: editing.references, signals: editing.signals,
      }, options)
    } else if (proposal) {
      router.post(acceptHalonSkillProposalPath(proposal.id), params, options)
    } else {
      router.post(halonSkillsPath(), params, options)
    }
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>{titleFor(state)}</DialogTitle>
            <DialogDescription>
              {proposal
                ? "Change what Halon wrote, then accept it. It goes live as your version, and Halon's stays in the history."
                : "Halon sees the name and when it is used, and loads the steps when a question fits. The tools it names become callable for whoever is asking, as far as their permissions reach."}
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 py-4">
            <FormErrors errors={omitErrors(errors, ...FIELDS_WITH_OWN_ERRORS)} />
            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("name")}>Name</Label>
              <Blocked reason={renameBlocked} side="top" className="block">
                <Input
                  id={fieldId("name")}
                  value={draft.name}
                  onChange={writeName}
                  placeholder="rotate_api_keys"
                  maxLength={SKILL_LIMITS.NAME}
                  disabled={Boolean(renameBlocked)}
                  className="font-mono"
                  aria-invalid={Boolean(errors.name)}
                />
              </Blocked>
              {copyOf && (
                <p className="text-xs text-muted-foreground">
                  Keep the name {copyOf} so Halon uses this in place of Firefight&apos;s skill of that name.
                </p>
              )}
              {messageOf(errors, "name") && <p className="text-xs text-destructive">{messageOf(errors, "name")}</p>}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("when")}>When Halon uses it</Label>
              <Textarea
                id={fieldId("when")}
                value={draft.usedWhen}
                onChange={writeWhen}
                rows={2}
                maxLength={SKILL_LIMITS.WHEN}
                placeholder="Someone asks to rotate the API keys of a service"
                aria-invalid={Boolean(errors.when)}
              />
              {messageOf(errors, "when") && <p className="text-xs text-destructive">{messageOf(errors, "when")}</p>}
            </div>
            <div className="flex flex-col gap-2">
              <Label>Tools</Label>
              <SearchableMultiSelect
                value={draft.tools}
                onValueChange={pickTools}
                options={options}
                placeholder={toolsLoaded ? "Choose the tools its steps call" : "Loading the tools Halon has here"}
                addMoreText="Add another tool"
                searchPlaceholder="Search tools"
                emptyText={toolsLoaded ? "No tool has that name" : "Loading tools"}
                renderBadge={renderToolBadge}
                renderOption={renderToolOption}
              />
              {messageOf(errors, "tools") && <p className="text-xs text-destructive">{messageOf(errors, "tools")}</p>}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("steps")}>Steps</Label>
              <MarkdownEditor
                id={fieldId("steps")}
                value={draft.steps}
                onChange={writeSteps}
                placeholder="1. Find the service on the map with `get_resource_map`."
                allowSource
                minHeight="min-h-56"
              />
              <p className="text-xs text-muted-foreground">Number the steps and name each tool in backticks, as Firefight&apos;s own skills do.</p>
              {messageOf(errors, "steps") && <p className="text-xs text-destructive">{messageOf(errors, "steps")}</p>}
            </div>
            {editing && (
              <div className="flex flex-col gap-2">
                <Label htmlFor={fieldId("reason")}>What changed (optional)</Label>
                <Input
                  id={fieldId("reason")}
                  value={draft.reason}
                  onChange={writeReason}
                  maxLength={SKILL_LIMITS.REASON}
                  placeholder="Ask the owning team before rotating"
                />
              </div>
            )}
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>
              {proposal ? "Accept with my edit" : editing ? "Save version" : "Add skill"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
