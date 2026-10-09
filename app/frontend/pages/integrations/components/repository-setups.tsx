import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconDotsVertical, IconPlus } from "@tabler/icons-react"

import { deriveIntegrationRepositorySetupPath, integrationRepositorySetupPath } from "@/lib/routes"
import { andList } from "@/lib/formatters"
import { timeAgo } from "@/lib/time"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import {
  RepositorySetupDialog,
  type RepositorySetupDialogState,
} from "@/pages/integrations/components/repository-setup-dialog"
import type { RepositorySetup } from "@/types/serializers"

function originWords(setup: RepositorySetup) {
  if (setup.editedAt) {
    return `Changed here ${timeAgo(setup.editedAt)}`
  }
  if (setup.derivedFrom && setup.derivedAt) {
    return `Read from ${setup.derivedFrom} ${timeAgo(setup.derivedAt)}`
  }
  return "Set up here"
}

function serviceWords(service: RepositorySetup["services"][number]) {
  const image = service.image ? ` (${service.image})` : ""
  const port = service.port ? ` on port ${service.port}` : ""
  return `${service.name}${image}${port}`
}

// How each repository the connection holds is set up before a code change or a test run: the services, variables and
// commands its CI uses, read from CI the first time Halon prepares it. An admin adds one, changes one, reads one from CI
// again or clears it, and each says so in a toast.
export function RepositorySetups({
  integrationId,
  setups,
  canManage,
}: {
  integrationId: string
  setups: RepositorySetup[]
  canManage: boolean
}) {
  const [dialog, setDialog] = useState<RepositorySetupDialogState>(null)
  const [clearing, setClearing] = useState<RepositorySetup | null>(null)
  const [rereading, setRereading] = useState<RepositorySetup | null>(null)

  function add() {
    setDialog({ mode: "create" })
  }

  function edit(setup: RepositorySetup) {
    setDialog({ mode: "edit", setup })
  }

  function closeDialog() {
    setDialog(null)
  }

  function readAgain(setup: RepositorySetup) {
    router.post(deriveIntegrationRepositorySetupPath(integrationId, setup.id), {}, { preserveScroll: true, preserveState: true })
  }

  // Reading again replaces what an admin changed, so it asks first. A setup nobody changed is read again at once.
  function askToReadAgain(setup: RepositorySetup) {
    if (setup.editedAt) {
      setRereading(setup)
      return
    }
    readAgain(setup)
  }

  function confirmReadAgain() {
    if (rereading) {
      readAgain(rereading)
    }
    setRereading(null)
  }

  function cancelReadAgain() {
    setRereading(null)
  }

  function confirmClear() {
    if (clearing) {
      router.delete(integrationRepositorySetupPath(integrationId, clearing.id), { preserveScroll: true, preserveState: true })
    }
    setClearing(null)
  }

  function cancelClear() {
    setClearing(null)
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-medium">Repository setup</p>
        {canManage && (
          <Button size="sm" variant="outline" onClick={add}>
            <IconPlus className="size-4" />
            Set up a repository
          </Button>
        )}
      </div>
      <div className="border-border flex flex-col rounded-lg border">
        <p className="text-muted-foreground border-border border-b px-3 py-2.5 text-xs">
          Before a code change or a test run, Halon starts the services, sets the variables and runs the commands a
          repository&apos;s CI uses. It reads them from CI the first time it prepares a repository.
        </p>
        {setups.length === 0 ? (
          <p className="text-muted-foreground px-3 py-2.5 text-sm">
            No repository is set up yet. Halon reads each one from its CI when it first prepares it.
          </p>
        ) : (
          setups.map((setup) => (
            <SetupRow
              key={setup.id}
              setup={setup}
              canManage={canManage}
              onEdit={edit}
              onReadAgain={askToReadAgain}
              onClear={setClearing}
            />
          ))
        )}
      </div>

      <RepositorySetupDialog integrationId={integrationId} state={dialog} onClose={closeDialog} />

      <ConfirmDeleteDialog
        open={Boolean(clearing)}
        title={`Clear ${clearing?.repository ?? ""}'s setup?`}
        description={`Halon forgets the services, variables and commands kept for ${clearing?.repository ?? ""}, changes made here included. It reads them from the repository's CI again the next time it prepares it for a code change or a test run.`}
        confirmLabel="Clear"
        onConfirm={confirmClear}
        onCancel={cancelClear}
      />

      <ConfirmDeleteDialog
        open={Boolean(rereading)}
        title={`Read ${rereading?.repository ?? ""}'s setup from CI again?`}
        description="This replaces the changes made here with what the repository's CI says now."
        confirmLabel="Read from CI"
        confirmVariant="default"
        onConfirm={confirmReadAgain}
        onCancel={cancelReadAgain}
      />
    </div>
  )
}

function SetupRow({
  setup,
  canManage,
  onEdit,
  onReadAgain,
  onClear,
}: {
  setup: RepositorySetup
  canManage: boolean
  onEdit: (setup: RepositorySetup) => void
  onReadAgain: (setup: RepositorySetup) => void
  onClear: (setup: RepositorySetup) => void
}) {
  const variables = Object.entries(setup.env)

  function edit() {
    onEdit(setup)
  }

  function readAgain() {
    onReadAgain(setup)
  }

  function clear() {
    onClear(setup)
  }

  return (
    <div className="border-border flex flex-col gap-2 border-b px-3 py-2.5 last:border-b-0">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="truncate font-mono text-sm">{setup.repository}</p>
          <p className="text-muted-foreground text-xs">{originWords(setup)}</p>
        </div>
        {canManage && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" className="text-muted-foreground size-8">
                <IconDotsVertical className="size-4" />
                <span className="sr-only">Actions for {setup.repository}</span>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-44">
              <DropdownMenuItem onSelect={edit}>Edit</DropdownMenuItem>
              <DropdownMenuItem onSelect={readAgain}>Read from CI again</DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem variant="destructive" onSelect={clear}>Clear</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>

      <dl className="grid grid-cols-[6rem_1fr] gap-x-3 gap-y-1.5 text-xs">
        <dt className="text-muted-foreground">Services</dt>
        <dd>{setup.services.length === 0 ? "None" : setup.services.map(serviceWords).join(", ")}</dd>
        <dt className="text-muted-foreground">Variables</dt>
        <dd className="min-w-0">
          {variables.length === 0 ? (
            "None"
          ) : (
            <pre className="bg-muted overflow-x-auto rounded px-2 py-1 font-mono">
              {variables.map(([name, value]) => `${name}=${value}`).join("\n")}
            </pre>
          )}
        </dd>
        <dt className="text-muted-foreground">Commands</dt>
        <dd className="flex min-w-0 flex-col gap-1">
          {setup.commands.length === 0
            ? "None"
            : setup.commands.map((command, index) => (
                <pre key={`${setup.id}-command-${index}`} className="bg-muted overflow-x-auto rounded px-2 py-1 font-mono">
                  {command}
                </pre>
              ))}
        </dd>
      </dl>

      {setup.unstartableServices.length > 0 && (
        <p className="border-warning-border bg-warning-tint rounded-md border px-2 py-1.5 text-xs">
          The sandbox cannot start {andList(setup.unstartableServices)}, so Halon prepares {setup.repository} without{" "}
          {setup.unstartableServices.length === 1 ? "it" : "them"}.
        </p>
      )}

      {setup.notes.length > 0 && (
        <ul className="text-muted-foreground flex list-disc flex-col gap-0.5 pl-4 text-xs">
          {setup.notes.map((note, index) => (
            <li key={`${setup.id}-note-${index}`}>{note}</li>
          ))}
        </ul>
      )}
    </div>
  )
}
