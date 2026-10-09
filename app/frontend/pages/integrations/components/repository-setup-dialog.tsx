import { useState, type ChangeEvent, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import type { Errors } from "@inertiajs/core"
import { IconPlus, IconX } from "@tabler/icons-react"

import { integrationRepositorySetupPath, integrationRepositorySetupsPath } from "@/lib/routes"
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
import { andList } from "@/lib/formatters"
import { SANDBOX_SERVICES } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import type { RepositorySetup } from "@/types/serializers"

export type RepositorySetupDialogState = { mode: "create" } | { mode: "edit"; setup: RepositorySetup } | null

type ServiceDraft = { key: number; name: string; image: string; port: string; env: string }
type CommandDraft = { key: number; text: string }
type Draft = { repository: string; services: ServiceDraft[]; env: string; commands: CommandDraft[] }

let nextKey = 0

function commandDraft(text = ""): CommandDraft {
  nextKey += 1
  return { key: nextKey, text }
}

function variableLines(env: Record<string, string>) {
  return Object.entries(env)
    .map(([name, value]) => `${name}=${value}`)
    .join("\n")
}

// NAME=value a line, as the page shows them. A line without = is a name with no value.
function variablePairs(text: string) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => {
      const split = line.indexOf("=")
      return split === -1 ? { name: line, value: "" } : { name: line.slice(0, split).trim(), value: line.slice(split + 1) }
    })
}

function serviceDraft(service?: RepositorySetup["services"][number]): ServiceDraft {
  nextKey += 1
  return {
    key: nextKey,
    name: service?.name ?? "",
    image: service?.image ?? "",
    port: service?.port ? String(service.port) : "",
    env: service ? variableLines(service.env) : "",
  }
}

function draftOf(setup: RepositorySetup | null): Draft {
  return {
    repository: setup?.repository ?? "",
    services: setup?.services.map(serviceDraft) ?? [],
    env: setup ? variableLines(setup.env) : "",
    commands: setup?.commands.map((command) => commandDraft(command)) ?? [],
  }
}

function sentOf(draft: Draft) {
  return {
    services: draft.services.map((service) => ({
      name: service.name,
      image: service.image,
      port: service.port,
      env: variablePairs(service.env),
    })),
    env: variablePairs(draft.env),
    commands: draft.commands.map((command) => command.text),
  }
}

// Owns both setting a repository up and changing its setup. A new one starts from its name: Halon reads the rest from
// its CI, or the admin chooses to set it up by hand. A refusal stays beside what was typed.
export function RepositorySetupDialog({
  integrationId,
  state,
  onClose,
}: {
  integrationId: string
  state: RepositorySetupDialogState
  onClose: () => void
}) {
  const editing = state?.mode === "edit" ? state.setup : null
  const [draft, setDraft] = useState<Draft>(draftOf(null))
  const [byHand, setByHand] = useState(false)
  const [errors, setErrors] = useState<Errors>({})
  const [processing, setProcessing] = useState(false)

  // Re-seed when the dialog opens, and when it is reused for another repository.
  const identity = `${state?.mode ?? "closed"}:${editing?.id ?? ""}`
  const [lastIdentity, setLastIdentity] = useState<string | null>(null)
  if (state && identity !== lastIdentity) {
    setLastIdentity(identity)
    setDraft(draftOf(editing))
    setByHand(Boolean(editing))
    setErrors({})
  }

  const fieldId = (field: string) => `repository-setup-${field}-${editing?.id ?? "new"}`

  function finish() {
    setProcessing(false)
  }

  const options = { preserveScroll: true, preserveState: true, onSuccess: onClose, onError: setErrors, onFinish: finish }

  function save(event: FormEvent) {
    event.preventDefault()
    setProcessing(true)
    if (editing) {
      router.patch(integrationRepositorySetupPath(integrationId, editing.id), sentOf(draft), options)
    } else {
      router.post(integrationRepositorySetupsPath(integrationId), { repository: draft.repository, ...sentOf(draft) }, options)
    }
  }

  function readFromCi() {
    setProcessing(true)
    router.post(integrationRepositorySetupsPath(integrationId), { repository: draft.repository, read_from_ci: true }, options)
  }

  function setUpByHand() {
    setByHand(true)
  }

  function editRepository(event: ChangeEvent<HTMLInputElement>) {
    setDraft({ ...draft, repository: event.target.value })
  }

  function editVariables(event: ChangeEvent<HTMLTextAreaElement>) {
    setDraft({ ...draft, env: event.target.value })
  }

  function addService() {
    setDraft({ ...draft, services: [...draft.services, serviceDraft()] })
  }

  function changeService(key: number, field: keyof Omit<ServiceDraft, "key">, value: string) {
    setDraft({
      ...draft,
      services: draft.services.map((service) => (service.key === key ? { ...service, [field]: value } : service)),
    })
  }

  function removeService(key: number) {
    setDraft({ ...draft, services: draft.services.filter((service) => service.key !== key) })
  }

  function addCommand() {
    setDraft({ ...draft, commands: [...draft.commands, commandDraft()] })
  }

  function changeCommand(key: number, text: string) {
    setDraft({ ...draft, commands: draft.commands.map((command) => (command.key === key ? { ...command, text } : command)) })
  }

  function removeCommand(key: number) {
    setDraft({ ...draft, commands: draft.commands.filter((command) => command.key !== key) })
  }

  const title = editing ? `Edit ${editing.repository}'s setup` : "Set up a repository"
  const repositoryError = errors.repository

  return (
    <Dialog open={Boolean(state)} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
        <form onSubmit={save}>
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            <DialogDescription>
              Before a code change or a test run, Halon starts these services, sets these variables and runs these
              commands in the repository, as its CI does.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-5 py-4">
            {!editing && (
              <div className="flex flex-col gap-2">
                <Label htmlFor={fieldId("repository")}>Repository</Label>
                <Input
                  id={fieldId("repository")}
                  placeholder="acme/api"
                  value={draft.repository}
                  onChange={editRepository}
                  aria-invalid={Boolean(repositoryError)}
                  spellCheck={false}
                  className="font-mono"
                />
                {repositoryError && <p className="text-destructive text-xs">{repositoryError}</p>}
                {!byHand && (
                  <p className="text-muted-foreground text-xs">
                    Halon reads the services, variables and commands from the repository&apos;s CI. You can change them
                    afterwards.
                  </p>
                )}
              </div>
            )}

            {byHand && (
              <>
                <div className="flex flex-col gap-2">
                  <div className="flex items-center justify-between gap-2">
                    <Label>Services</Label>
                    <Button type="button" size="sm" variant="ghost" onClick={addService}>
                      <IconPlus className="size-4" />
                      Add service
                    </Button>
                  </div>
                  {draft.services.length === 0 && (
                    <p className="text-muted-foreground text-xs">No services. The sandbox can start {andList([...SANDBOX_SERVICES])}.</p>
                  )}
                  {draft.services.map((service, index) => (
                    <ServiceFields
                      key={service.key}
                      service={service}
                      position={index + 1}
                      onChange={changeService}
                      onRemove={removeService}
                    />
                  ))}
                </div>

                <div className="flex flex-col gap-2">
                  <Label htmlFor={fieldId("env")}>Variables</Label>
                  <Textarea
                    id={fieldId("env")}
                    rows={4}
                    placeholder={"RAILS_ENV=test\nDATABASE_URL=postgres://postgres@127.0.0.1:5432/app_test"}
                    value={draft.env}
                    onChange={editVariables}
                    spellCheck={false}
                    className="font-mono text-xs md:text-xs"
                  />
                  <p className="text-muted-foreground text-xs">
                    One per line, as NAME=value. The sandbox&apos;s services take any password, so leave passwords out.
                  </p>
                </div>

                <div className="flex flex-col gap-2">
                  <div className="flex items-center justify-between gap-2">
                    <Label>Commands</Label>
                    <Button type="button" size="sm" variant="ghost" onClick={addCommand}>
                      <IconPlus className="size-4" />
                      Add command
                    </Button>
                  </div>
                  {draft.commands.length === 0 && (
                    <p className="text-muted-foreground text-xs">
                      No commands. Halon still installs what the lockfiles and version files ask for.
                    </p>
                  )}
                  {draft.commands.map((command, index) => (
                    <CommandField
                      key={command.key}
                      command={command}
                      position={index + 1}
                      onChange={changeCommand}
                      onRemove={removeCommand}
                    />
                  ))}
                  <p className="text-muted-foreground text-xs">
                    They run in order from the repository&apos;s root, each as one script, before the tests. Leave the
                    test command itself out.
                  </p>
                </div>

                {errors.setup && <p className="text-destructive text-xs">{errors.setup}</p>}
              </>
            )}
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            {!byHand && (
              <>
                <Button variant="outline" type="button" onClick={setUpByHand} disabled={processing}>
                  Set up by hand
                </Button>
                <Button type="button" onClick={readFromCi} disabled={processing}>
                  Read from CI
                </Button>
              </>
            )}
            {byHand && (
              <Button type="submit" disabled={processing}>
                Save
              </Button>
            )}
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function ServiceFields({
  service,
  position,
  onChange,
  onRemove,
}: {
  service: ServiceDraft
  position: number
  onChange: (key: number, field: keyof Omit<ServiceDraft, "key">, value: string) => void
  onRemove: (key: number) => void
}) {
  const id = (field: string) => `repository-setup-service-${service.key}-${field}`

  function editName(event: ChangeEvent<HTMLInputElement>) {
    onChange(service.key, "name", event.target.value)
  }

  function editImage(event: ChangeEvent<HTMLInputElement>) {
    onChange(service.key, "image", event.target.value)
  }

  function editPort(event: ChangeEvent<HTMLInputElement>) {
    onChange(service.key, "port", event.target.value)
  }

  function editVariables(event: ChangeEvent<HTMLTextAreaElement>) {
    onChange(service.key, "env", event.target.value)
  }

  function remove() {
    onRemove(service.key)
  }

  return (
    <div className="border-border flex flex-col gap-2 rounded-md border p-2.5">
      <div className="grid grid-cols-[1fr_1fr_6rem_auto] items-end gap-2">
        <div className="flex flex-col gap-1">
          <Label htmlFor={id("name")} className="text-xs">Name</Label>
          <Input id={id("name")} placeholder="postgres" value={service.name} onChange={editName} spellCheck={false} />
        </div>
        <div className="flex flex-col gap-1">
          <Label htmlFor={id("image")} className="text-xs">Image in CI</Label>
          <Input id={id("image")} placeholder="postgres:16" value={service.image} onChange={editImage} spellCheck={false} />
        </div>
        <div className="flex flex-col gap-1">
          <Label htmlFor={id("port")} className="text-xs">Port</Label>
          <Input id={id("port")} placeholder="5432" inputMode="numeric" value={service.port} onChange={editPort} />
        </div>
        <Button type="button" size="icon" variant="ghost" onClick={remove} className="size-9">
          <IconX className="size-4" />
          <span className="sr-only">Remove service {position}</span>
        </Button>
      </div>
      <div className="flex flex-col gap-1">
        <Label htmlFor={id("env")} className="text-xs">Its variables</Label>
        <Textarea
          id={id("env")}
          rows={2}
          placeholder="POSTGRES_DB=app_test"
          value={service.env}
          onChange={editVariables}
          spellCheck={false}
          className="min-h-0 font-mono text-xs md:text-xs"
        />
      </div>
    </div>
  )
}

// A command is one script, so it keeps as many lines as it has, up to a few before it scrolls.
function commandRows(text: string) {
  return Math.min(Math.max(text.split("\n").length, 1), 8)
}

function CommandField({
  command,
  position,
  onChange,
  onRemove,
}: {
  command: CommandDraft
  position: number
  onChange: (key: number, text: string) => void
  onRemove: (key: number) => void
}) {
  function edit(event: ChangeEvent<HTMLTextAreaElement>) {
    onChange(command.key, event.target.value)
  }

  function remove() {
    onRemove(command.key)
  }

  return (
    <div className="flex items-start gap-2">
      <Textarea
        aria-label={`Command ${position}`}
        rows={commandRows(command.text)}
        placeholder="bin/rails db:prepare"
        value={command.text}
        onChange={edit}
        spellCheck={false}
        className="min-h-0 font-mono text-xs md:text-xs"
      />
      <Button type="button" size="icon" variant="ghost" onClick={remove} className="size-9 shrink-0">
        <IconX className="size-4" />
        <span className="sr-only">Remove command {position}</span>
      </Button>
    </div>
  )
}
