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
import { PermissionsMatrix } from "@/pages/settings/components/permissions-matrix"
import { permsToHash, usePermissionsMatrix } from "@/pages/settings/hooks/use-permissions-matrix"

export function CreateKeyDialog() {
  const [open, setOpen] = useState(false)
  const { perms, togglePerm, reset: resetPerms } = usePermissionsMatrix()
  const form = useForm({ name: "", expires_at: "", permissions: {} as Record<string, string[]> })

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    form.transform(() => ({
      name: form.data.name,
      expires_at: form.data.expires_at || undefined,
      permissions: permsToHash(perms),
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
          Create Key
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Create API Key</DialogTitle>
            <DialogDescription>
              Generate a new API key with specific permissions.
              The token will only be shown once after creation.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
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
            <Separator />
            <div className="flex flex-col gap-3">
              <Label className="text-sm font-medium">Permissions</Label>
              <PermissionsMatrix perms={perms} onToggle={togglePerm} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              Create Key
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
