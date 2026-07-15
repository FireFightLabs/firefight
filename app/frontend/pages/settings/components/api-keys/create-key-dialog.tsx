import { useState, type FormEvent } from "react"
import { useForm } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import { apiKeysPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { PermissionsMatrix } from "@/pages/settings/components/api-keys/permissions-matrix"
import { permsToHash, usePermissionsMatrix } from "@/pages/settings/hooks/use-permissions-matrix"

export function CreateKeyDialog({ canManageServiceKeys }: { canManageServiceKeys: boolean }) {
  const [open, setOpen] = useState(false)
  const [kind, setKind] = useState<"personal" | "service">(canManageServiceKeys ? "service" : "personal")
  const { perms, togglePerm, reset: resetPerms } = usePermissionsMatrix()
  const form = useForm({ name: "", expires_at: "", permissions: {} as Record<string, string[]> })

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    form.transform(() => ({
      kind,
      name: form.data.name,
      expires_at: form.data.expires_at || undefined,
      permissions: kind === "personal" ? {} : permsToHash(perms),
    }))
    form.post(apiKeysPath(), {
      onSuccess: () => {
        setOpen(false)
        form.reset()
        resetPerms()
      },
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm">
          <IconPlus className="size-4" />
          Create key
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Create API key</DialogTitle>
            <DialogDescription>
              The token is shown once after creation.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label>Kind</Label>
              <div className="flex flex-col gap-2">
                <label className="flex cursor-pointer items-start gap-2.5 rounded-md border border-input p-3 text-sm has-[:checked]:border-primary">
                  <input
                    type="radio"
                    name="key-kind"
                    checked={kind === "personal"}
                    onChange={() => setKind("personal")}
                    className="mt-0.5"
                  />
                  <span>
                    <span className="font-medium">Personal token — acts as you</span>
                    <span className="block text-xs text-muted-foreground">
                      Read access to everything you can see. For your own agent sessions (Claude Code, Cursor).
                      Revoked automatically if you leave the workspace.
                    </span>
                  </span>
                </label>
                {canManageServiceKeys && (
                  <label className="flex cursor-pointer items-start gap-2.5 rounded-md border border-input p-3 text-sm has-[:checked]:border-primary">
                    <input
                      type="radio"
                      name="key-kind"
                      checked={kind === "service"}
                      onChange={() => setKind("service")}
                      className="mt-0.5"
                    />
                    <span>
                      <span className="font-medium">Workspace service key</span>
                      <span className="block text-xs text-muted-foreground">
                        Its own identity with explicit permission scopes. For integrations, CI, and headless agents.
                      </span>
                    </span>
                  </label>
                )}
              </div>
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="key-name">Name</Label>
              <Input
                id="key-name"
                placeholder="e.g. Production Integration"
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
              />
              {form.errors.name && (
                <p className="text-xs text-destructive">{form.errors.name}</p>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="key-expires">Expiration (optional)</Label>
              <Input
                id="key-expires"
                type="date"
                value={form.data.expires_at}
                onChange={(e) => form.setData("expires_at", e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                Leave empty for a non-expiring key.
              </p>
            </div>
            {kind === "service" && (
              <>
                <Separator />
                <div className="flex flex-col gap-3">
                  <Label className="text-sm font-medium">Permissions</Label>
                  <PermissionsMatrix perms={perms} onToggle={togglePerm} />
                </div>
              </>
            )}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              Create key
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
