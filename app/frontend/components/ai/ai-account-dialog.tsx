import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import type { Errors } from "@inertiajs/core"

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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { whenClosed } from "@/lib/handlers"
import { aiAccountPath, aiAccountsPath } from "@/lib/routes"
import { FormErrors } from "@/components/form-errors"
import { AiAccountModelField } from "@/components/ai/ai-account-model-field"
import type { AiProviderOption, WorkspaceAiAccount } from "@/types/serializers"

export type AiAccountDialogState = { mode: "create" } | { mode: "edit"; account: WorkspaceAiAccount } | null

interface Draft {
  provider: string
  label: string
  settings: Record<string, string>
  main: string
  fast: string
}

// Secrets are never sent to the page, so an edit starts them empty and an empty one keeps what is stored.
function draftFor(account: WorkspaceAiAccount | null, provider: AiProviderOption | undefined): Draft {
  return {
    provider: account?.provider ?? provider?.slug ?? "",
    label: account?.label ?? provider?.name ?? "",
    settings: { ...(account?.settings ?? {}) },
    main: account?.models.main ?? provider?.mainModel ?? "",
    fast: account?.models.fast ?? provider?.fastModel ?? "",
  }
}

function errorText(value: unknown): string | null {
  if (!value) {
    return null
  }
  return Array.isArray(value) ? value.join(" ") : String(value)
}

export function AiAccountDialog({
  state,
  providers,
  onClose,
}: {
  state: AiAccountDialogState
  providers: AiProviderOption[]
  onClose: () => void
}) {
  const editing = state?.mode === "edit" ? state.account : null
  const [draft, setDraft] = useState<Draft>(() => draftFor(null, providers[0]))
  const [errors, setErrors] = useState<Errors>({})
  const [processing, setProcessing] = useState(false)

  // Seeded again each time it opens, and when it is reused for another account.
  const identity = `${state?.mode ?? "closed"}:${editing?.id ?? ""}`
  const [lastIdentity, setLastIdentity] = useState<string | null>(null)
  if (state && identity !== lastIdentity) {
    setLastIdentity(identity)
    setDraft(draftFor(editing, editing ? providers.find((option) => option.slug === editing.provider) : providers[0]))
    setErrors({})
  }
  if (!state && lastIdentity !== null) {
    setLastIdentity(null)
  }

  const provider = providers.find((option) => option.slug === draft.provider)
  const fieldId = (field: string) => `ai-account-${field}-${editing?.id ?? "new"}`
  const baseErrors = errorText(errors.base)
  const keyField = provider?.fields.find((candidate) => candidate.secret)
  const keySummary = editing?.keySummary

  // A new provider brings its own settings and recommended models. A label still reading the old provider's name follows it.
  function chooseProvider(slug: string) {
    const chosen = providers.find((option) => option.slug === slug)
    const previous = providers.find((option) => option.slug === draft.provider)
    setDraft({
      provider: slug,
      label: !draft.label || draft.label === previous?.name ? chosen?.name ?? "" : draft.label,
      settings: {},
      main: chosen?.mainModel ?? "",
      fast: chosen?.fastModel ?? "",
    })
  }

  function changeLabel(event: React.ChangeEvent<HTMLInputElement>) {
    setDraft({ ...draft, label: event.target.value })
  }

  function changeSetting(key: string, value: string) {
    setDraft({ ...draft, settings: { ...draft.settings, [key]: value } })
  }

  function changeMain(value: string) {
    setDraft({ ...draft, main: value })
  }

  function changeFast(value: string) {
    setDraft({ ...draft, fast: value })
  }

  function finish() {
    setProcessing(false)
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setProcessing(true)
    const params = {
      provider: draft.provider,
      label: draft.label,
      settings: draft.settings,
      models: { main: draft.main, fast: draft.fast },
    }
    const options = { preserveScroll: true, onSuccess: onClose, onError: setErrors, onFinish: finish }

    if (editing) {
      router.patch(aiAccountPath(editing.id), params, options)
    } else {
      router.post(aiAccountsPath(), params, options)
    }
  }

  return (
    <Dialog open={Boolean(state)} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>{editing ? `Edit ${editing.label}` : "Add an AI account"}</DialogTitle>
            <DialogDescription>
              {editing
                ? "Change its settings or models. Leave a key empty to keep the one saved. Saving checks the account again."
                : "Halon will use this account's own key. Saving checks it with one short call to the provider."}
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 py-4">
            {baseErrors && <FormErrors errors={baseErrors} />}

            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("provider")}>Provider</Label>
              <Select value={draft.provider} onValueChange={chooseProvider} disabled={Boolean(editing)}>
                <SelectTrigger id={fieldId("provider")} className="w-full">
                  <SelectValue placeholder="Choose a provider" />
                </SelectTrigger>
                <SelectContent>
                  {providers.map((option) => (
                    <SelectItem key={option.slug} value={option.slug}>
                      {option.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {errorText(errors.provider) && <p className="text-xs text-destructive">{errorText(errors.provider)}</p>}
              {provider && !provider.codeFixes && (
                <p className="text-xs text-muted-foreground">
                  Halon answers and investigates on this provider. Code fixes need an Anthropic, OpenAI or OpenRouter account, so a
                  fix uses the next account in the list that is one.
                </p>
              )}
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor={fieldId("label")}>Name</Label>
              <Input id={fieldId("label")} value={draft.label} onChange={changeLabel} placeholder="What your team calls this account" />
              {errorText(errors.label) && <p className="text-xs text-destructive">{errorText(errors.label)}</p>}
            </div>

            {provider?.fields.map((field) => (
              <div key={field.key} className="flex flex-col gap-2">
                <Label htmlFor={fieldId(field.key)}>
                  {field.label}
                  {!field.required && <span className="font-normal text-muted-foreground"> (optional)</span>}
                </Label>
                <Input
                  id={fieldId(field.key)}
                  type={field.secret ? "password" : "text"}
                  autoComplete="off"
                  value={draft.settings[field.key] ?? ""}
                  onChange={(event) => changeSetting(field.key, event.target.value)}
                  placeholder={field.secret && keySummary ? "Unchanged" : undefined}
                />
                {keySummary && field.key === keyField?.key && <p className="text-xs text-muted-foreground">{keySummary}</p>}
              </div>
            ))}

            <AiAccountModelField
              id={fieldId("main")}
              label="Main model"
              hint="Investigations, chats, postmortems and code fixes."
              provider={provider}
              value={draft.main}
              error={errorText(errors["models.main"])}
              onChange={changeMain}
            />
            <AiAccountModelField
              id={fieldId("fast")}
              label="Quick model"
              hint="Summaries, timeline notes and replies to mentions."
              provider={provider}
              value={draft.fast}
              error={errorText(errors["models.fast"])}
              onChange={changeFast}
            />
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing || !provider}>
              {processing ? "Checking" : editing ? "Save and check" : "Add and check"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
