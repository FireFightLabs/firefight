import { useForm } from "@inertiajs/react"
import { type ChangeEvent, type FormEvent } from "react"

import { SearchableSelect } from "@/components/searchable-select"
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
import { whenClosed } from "@/lib/handlers"
import { HANDBOOK_SOURCE_KINDS } from "@/lib/generated/constants"
import { handbookSourcesPath } from "@/lib/routes"
import type { HandbookImporter } from "@/types/serializers"

interface ImportDialogProps {
  open: boolean
  importers: HandbookImporter[]
  onClose: () => void
}

// Brings in docs a team already keeps, as pages synced from a file or folder in a repository or from a document in a
// connected tool. Each connection that can be read from is offered, and its repositories come from the map.
export function ImportDialog({ open, importers, onClose }: ImportDialogProps) {
  const first = importers[0]
  const { data, setData, post, processing, reset } = useForm({
    integration_id: first?.id ?? "",
    kind: first?.kind ?? HANDBOOK_SOURCE_KINDS.REPOSITORY,
    repository: first?.repositories[0] ?? "",
    path: "",
    reference: "",
  })
  const importer = importers.find((each) => each.id === data.integration_id) ?? null
  const fromRepository = importer?.kind === HANDBOOK_SOURCE_KINDS.REPOSITORY
  const ready = importer !== null && (fromRepository ? data.repository.trim() !== "" && data.path.trim() !== "" : data.reference.trim() !== "")
  const connectionOptions = importers.map((each) => ({ value: each.id, label: each.name }))
  const repositoryOptions = (importer?.repositories ?? []).map((name) => ({ value: name, label: name }))

  function chooseConnection(value: string | null) {
    const chosen = importers.find((each) => each.id === value)
    if (chosen) {
      setData({ ...data, integration_id: chosen.id, kind: chosen.kind, repository: chosen.repositories[0] ?? "" })
    }
  }

  function chooseRepository(value: string | null) {
    setData("repository", value ?? "")
  }

  function writeRepository(event: ChangeEvent<HTMLInputElement>) {
    setData("repository", event.target.value)
  }

  function writePath(event: ChangeEvent<HTMLInputElement>) {
    setData("path", event.target.value)
  }

  function writeReference(event: ChangeEvent<HTMLInputElement>) {
    setData("reference", event.target.value)
  }

  function finish() {
    reset()
    onClose()
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    if (ready) {
      post(handbookSourcesPath(), { preserveScroll: true, onSuccess: finish })
    }
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Import docs</DialogTitle>
            <DialogDescription>
              Each file or document becomes a page Halon reads. Pages stay in step with their source, so change them there.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 pt-3 pb-5">
            <div className="flex flex-col gap-2">
              <Label htmlFor="handbook-import-connection">From</Label>
              <SearchableSelect id="handbook-import-connection" value={data.integration_id || null} onValueChange={chooseConnection}
                                options={connectionOptions} placeholder="Pick a connection" searchPlaceholder="Search connections" emptyText="No connections match" />
            </div>
            {fromRepository ? (
              <>
                <div className="flex flex-col gap-2">
                  <Label htmlFor="handbook-import-repository">Repository</Label>
                  {repositoryOptions.length > 0 ? (
                    <SearchableSelect id="handbook-import-repository" value={data.repository || null} onValueChange={chooseRepository}
                                      options={repositoryOptions} placeholder="Pick a repository" searchPlaceholder="Search repositories" emptyText="No repositories match" />
                  ) : (
                    <Input id="handbook-import-repository" value={data.repository} onChange={writeRepository} placeholder="owner/name" />
                  )}
                </div>
                <div className="flex flex-col gap-2">
                  <Label htmlFor="handbook-import-path">File or folder</Label>
                  <Input id="handbook-import-path" value={data.path} onChange={writePath} placeholder="Such as docs/, HANDBOOK.md or AGENTS.md" />
                  <p className="text-xs text-muted-foreground">A folder brings in its Markdown and text files, up to 50. Firefight reads the default branch, and reads it again whenever it changes.</p>
                </div>
              </>
            ) : (
              importer && (
                <div className="flex flex-col gap-2">
                  <Label htmlFor="handbook-import-reference">Page link</Label>
                  <Input id="handbook-import-reference" value={data.reference} onChange={writeReference} placeholder="Paste the page's link or id" />
                  <p className="text-xs text-muted-foreground">Firefight reads the page again every hour.</p>
                </div>
              )
            )}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" size="sm" disabled={processing}>
                Cancel
              </Button>
            </DialogClose>
            <Button type="submit" size="sm" disabled={processing || !ready}>
              {processing ? "Importing…" : "Import"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
