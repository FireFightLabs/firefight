import { useForm } from "@inertiajs/react"
import { type ChangeEvent, type FormEvent, type KeyboardEvent, useEffect } from "react"

import { MarkdownEditor } from "@/components/markdown-editor"
import { SearchableSelect } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { HANDBOOK_PAGE_KINDS, HANDBOOK_TEXT_LIMIT, HANDBOOK_TITLE_LIMIT } from "@/lib/generated/constants"
import { handbookPagePath, handbookPagesPath } from "@/lib/routes"
import { blankDraft, draftOf, type FreezeWindowDraft, FreezeWindowsEditor, windowOf } from "@/pages/handbook/components/freeze-windows-editor"
import type { HandbookPage, HandbookRole, HandbookSuggestion } from "@/types/serializers"

interface PageFormProps {
  page: HandbookPage | null
  suggestion: HandbookSuggestion | null
  roles: HandbookRole[]
  timeZones: string[]
  // The role Halon follows now, which a new page saying who directs it starts from.
  directingRoleName: string | null
  onDirtyChange: (dirty: boolean) => void
  onCancel: () => void
  onSaved: () => void
}

// Writes a new page or edits one, in place of reading it. Cmd or Ctrl with S saves.
export function PageForm({ page, suggestion, roles, timeZones, directingRoleName, onDirtyChange, onCancel, onSaved }: PageFormProps) {
  const directing = page ? page.kind === HANDBOOK_PAGE_KINDS.DIRECTING : Boolean(suggestion?.takesRole)
  const startingRole = page?.directingRoleId ?? roles.find((role) => role.name === directingRoleName)?.id ?? ""
  const startingWindows: FreezeWindowDraft[] = page ? page.freezeWindows.map(draftOf) : suggestion?.freezes ? [ blankDraft() ] : []
  // A page that freezes changes shows its windows before its words.
  const windowsFirst = startingWindows.length > 0
  const initial = {
    title: page?.title ?? suggestion?.title ?? "", text: page?.text ?? "", incident_role_id: directing ? startingRole : "", wording_id: page?.wordingId ?? "",
    freeze_windows: startingWindows,
  }
  const { data, setData, transform, post, patch, processing, isDirty, errors, clearErrors } = useForm(initial)
  const formErrors = errors as Partial<Record<"title" | "text" | "base" | "freeze_windows", string>>
  const title = data.title.trim()
  const text = data.text.trim()
  const missing = title.length === 0 || (directing ? data.incident_role_id === "" : text.length === 0 && data.freeze_windows.length === 0)
  const tooLong = title.length > HANDBOOK_TITLE_LIMIT || data.text.length > HANDBOOK_TEXT_LIMIT
  const roleOptions = roles.map((role) => ({ value: role.id, label: role.name }))

  useEffect(() => {
    onDirtyChange(isDirty)
  }, [ isDirty, onDirtyChange ])

  function save() {
    if (missing || tooLong || processing || !isDirty) {
      return
    }
    const options = { preserveScroll: true, onSuccess: onSaved }
    transform((form) => ({ ...form, freeze_windows: directing ? [] : form.freeze_windows.map(windowOf) }))
    if (page) {
      patch(handbookPagePath(page.id), options)
    } else {
      post(handbookPagesPath(), options)
    }
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    save()
  }

  function saveOnShortcut(event: KeyboardEvent<HTMLFormElement>) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
      event.preventDefault()
      save()
    }
  }

  function writeTitle(event: ChangeEvent<HTMLInputElement>) {
    setData("title", event.target.value)
    clearErrors("title")
  }

  function writeText(value: string) {
    setData("text", value)
  }

  function writeWindows(windows: FreezeWindowDraft[]) {
    setData("freeze_windows", windows)
  }

  function chooseRole(value: string | null) {
    if (value) {
      setData("incident_role_id", value)
    }
  }

  return (
    <form onSubmit={submit} onKeyDown={saveOnShortcut} className="flex flex-col gap-5">
      <div className="flex flex-col gap-2">
        <Label htmlFor="handbook-page-title">Title</Label>
        <Input id="handbook-page-title" value={data.title} onChange={writeTitle} maxLength={HANDBOOK_TITLE_LIMIT} placeholder="Such as How we release"
               autoFocus={!page} aria-invalid={Boolean(formErrors.title)} />
        {formErrors.title && <p className="text-sm text-destructive">Title {formErrors.title}</p>}
      </div>
      {suggestion && <p className="-mt-2 text-sm text-muted-foreground">{suggestion.hint}</p>}
      {directing && (
        <div className="flex flex-col gap-2">
          <Label htmlFor="handbook-directing-role">Halon takes direction from</Label>
          <SearchableSelect
            id="handbook-directing-role"
            value={data.incident_role_id || null}
            onValueChange={chooseRole}
            options={roleOptions}
            placeholder="Pick a role"
            searchPlaceholder="Search roles"
            emptyText="No roles match"
          />
          <p className="text-xs text-muted-foreground">When people in an incident ask for things that conflict, Halon says so and follows whoever holds this role.</p>
        </div>
      )}
      {!directing && windowsFirst && <FreezeWindowsEditor windows={data.freeze_windows} timeZones={timeZones} onChange={writeWindows} />}
      <div className="flex flex-col gap-2">
        <div className="flex items-baseline justify-between gap-3">
          <Label htmlFor="handbook-page-text">
            {directing ? "Anything else about who decides" : "Page"}{" "}
            {(directing || data.freeze_windows.length > 0) && <span className="font-normal text-muted-foreground">(optional)</span>}
          </Label>
          <span className={`text-xs tabular-nums ${data.text.length > HANDBOOK_TEXT_LIMIT ? "text-destructive" : "text-muted-foreground"}`}>
            {data.text.length.toLocaleString()} characters
          </span>
        </div>
        <MarkdownEditor
          id="handbook-page-text"
          value={data.text}
          onChange={writeText}
          allowSource
          minHeight="min-h-80"
          placeholder={suggestion ? `Such as: ${suggestion.example}` : "Write what Halon and your team should know. Headings split a long page into sections Halon can find."}
        />
      </div>
      {!directing && !windowsFirst && <FreezeWindowsEditor windows={data.freeze_windows} timeZones={timeZones} onChange={writeWindows} />}
      {(formErrors.base || formErrors.text || formErrors.freeze_windows) && (
        <p className="text-sm text-destructive">{formErrors.base ?? (formErrors.text ? `Page ${formErrors.text}` : `Freeze windows ${formErrors.freeze_windows}`)}</p>
      )}
      <div className="flex flex-wrap items-center justify-end gap-2 border-t pt-4">
        {page && <p className="mr-auto text-xs text-muted-foreground">The current wording is kept as history when you save.</p>}
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={processing}>
          Cancel
        </Button>
        <Button type="submit" size="sm" disabled={processing || missing || tooLong || !isDirty}>
          {processing ? "Saving…" : "Save page"}
        </Button>
      </div>
    </form>
  )
}
