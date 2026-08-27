import { useState } from "react"
import { useForm } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { whenClosed } from "@/lib/handlers"
import { gatewayAgentPath, gatewayAgentsPath } from "@/lib/routes"
import type { Agent } from "@/types/serializers"

// The slug is what a grant and the ledger record, so it is fixed once the
// agent exists. Only the name and description are editable afterwards.
function slugify(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 40)
}

export function AgentDialog({
  agent,
  open,
  onOpenChange,
}: {
  agent?: Agent
  open?: boolean
  onOpenChange?: (open: boolean) => void
}) {
  const [uncontrolled, setUncontrolled] = useState(false)
  const isOpen = open ?? uncontrolled
  const setOpen = onOpenChange ?? setUncontrolled
  const editing = Boolean(agent)

  const { data, setData, post, patch, processing, errors, reset } = useForm({
    name: agent?.name ?? "",
    slug: agent?.slug ?? "",
    description: agent?.description ?? "",
  })

  function close() {
    setOpen(false)
    if (!editing) {
      reset()
    }
  }

  function changeName(event: React.ChangeEvent<HTMLInputElement>) {
    const name = event.target.value
    setData(editing ? { ...data, name } : { ...data, name, slug: slugify(name) })
  }

  function changeSlug(event: React.ChangeEvent<HTMLInputElement>) {
    setData("slug", slugify(event.target.value))
  }

  function changeDescription(event: React.ChangeEvent<HTMLTextAreaElement>) {
    setData("description", event.target.value)
  }

  function submit(event: React.FormEvent) {
    event.preventDefault()
    const options = { preserveScroll: true, onSuccess: close }

    if (agent) {
      patch(gatewayAgentPath(agent.id), options)
    } else {
      post(gatewayAgentsPath(), options)
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={whenClosed(close)}>
      {!editing && (
        <DialogTrigger asChild>
          <Button size="sm" className="gap-1.5">
            <IconPlus className="size-4" />
            New agent
          </Button>
        </DialogTrigger>
      )}
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{editing ? `Edit ${agent?.name}` : "New agent"}</DialogTitle>
            <DialogDescription>
              {editing
                ? "The slug is fixed, since grants and the ledger record it."
                : "You get its token once, on the next screen. It starts with no abilities, so grant it what it needs under Permissions."}
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="agent-name">Name</Label>
              <Input id="agent-name" value={data.name} onChange={changeName} placeholder="Support agent" />
              {errors.name && <p className="text-xs text-destructive">{errors.name}</p>}
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="agent-slug">Slug</Label>
              <Input
                id="agent-slug"
                value={data.slug}
                onChange={changeSlug}
                disabled={editing}
                placeholder="support_agent"
                className="font-mono"
              />
              {errors.slug && <p className="text-xs text-destructive">{errors.slug}</p>}
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="agent-description">What it does</Label>
              <Textarea
                id="agent-description"
                rows={2}
                value={data.description}
                onChange={changeDescription}
                placeholder="Triages support tickets and opens incidents for confirmed bugs"
              />
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={close}>
              Never mind
            </Button>
            <Button type="submit" disabled={processing || !data.name || !data.slug}>
              {editing ? "Save" : "Create agent"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
