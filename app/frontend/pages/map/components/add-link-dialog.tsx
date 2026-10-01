import { useForm } from "@inertiajs/react"

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
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { RESOURCE_MAP_RELATIONS, type ResourceMapRelation } from "@/lib/generated/constants"
import { resourceMapLinksPath } from "@/lib/routes"
import { RELATION_SENTENCES } from "@/pages/map/lib/labels"
import type { ResourceMapResource } from "@/types/serializers"

interface AddLinkDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  resources: ResourceMapResource[]
  fromId: string | null
}

const DEFAULT_RELATION: ResourceMapRelation = "uses"

// A link a person knows and no provider reports, such as a service that uses a database it reaches by a secret.
export function AddLinkDialog({ open, onOpenChange, resources, fromId }: AddLinkDialogProps) {
  const { data, setData, post, processing, reset } = useForm({
    from_id: fromId ?? "",
    to_id: "",
    relation: DEFAULT_RELATION as ResourceMapRelation,
    note: "",
  })
  const options = resourceOptions(resources)
  const from = resources.find((resource) => resource.id === data.from_id)
  const to = resources.find((resource) => resource.id === data.to_id)

  function submit(event: React.FormEvent) {
    event.preventDefault()
    post(resourceMapLinksPath(), { preserveScroll: true, onSuccess: finish })
  }

  function finish() {
    reset()
    onOpenChange(false)
  }

  function chooseFrom(value: string | null) {
    setData("from_id", value ?? "")
  }

  function chooseTo(value: string | null) {
    setData("to_id", value ?? "")
  }

  function chooseRelation(value: string) {
    const relation = RESOURCE_MAP_RELATIONS.find((each) => each === value)
    if (relation) {
      setData("relation", relation)
    }
  }

  function writeNote(event: React.ChangeEvent<HTMLTextAreaElement>) {
    setData("note", event.target.value)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Add a link</DialogTitle>
            <DialogDescription>
              Say how one resource depends on another when no connection reports it. Halon and the map treat it as a fact.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 pt-3 pb-5">
            <div className="flex flex-col gap-2">
              <Label>Resource</Label>
              <SearchableSelect
                value={data.from_id || null}
                onValueChange={chooseFrom}
                options={options}
                placeholder="Pick the one that depends"
                searchPlaceholder="Search resources"
                emptyText="Nothing on the map matches"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="link-relation">How they are linked</Label>
              <Select value={data.relation} onValueChange={chooseRelation}>
                <SelectTrigger id="link-relation" className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {RESOURCE_MAP_RELATIONS.map((relation) => (
                    <SelectItem key={relation} value={relation}>
                      {RELATION_SENTENCES[relation]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-2">
              <Label>On</Label>
              <SearchableSelect
                value={data.to_id || null}
                onValueChange={chooseTo}
                options={options.filter((option) => option.value !== data.from_id)}
                placeholder="Pick what it depends on"
                searchPlaceholder="Search resources"
                emptyText="Nothing on the map matches"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="link-note">
                How you know <span className="font-normal text-muted-foreground">(optional)</span>
              </Label>
              <Textarea
                id="link-note"
                rows={2}
                className="resize-none"
                placeholder="Such as: its DATABASE_URL points at this branch"
                value={data.note}
                onChange={writeNote}
              />
            </div>
            {from && to && (
              <p className="rounded-lg bg-muted/40 px-3 py-2 text-sm text-muted-foreground">
                <span className="font-medium text-foreground">{from.name}</span> {RELATION_SENTENCES[data.relation]}{" "}
                <span className="font-medium text-foreground">{to.name}</span>
              </p>
            )}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" size="sm" disabled={processing}>
                Cancel
              </Button>
            </DialogClose>
            <Button type="submit" size="sm" disabled={processing || !from || !to}>
              {processing ? "Adding…" : "Add link"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function resourceOptions(resources: ResourceMapResource[]): SearchableSelectOption[] {
  return resources.map((resource) => ({ value: resource.id, label: `${resource.name} · ${resource.providerName}` }))
}
