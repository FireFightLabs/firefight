import { useEffect, useState } from "react"
import { router } from "@inertiajs/react"

import type { ApiKey as ApiKeyType } from "@/types/serializers"
import { apiKeyPath } from "@/lib/routes"
import { usePermissionsMatrix, permsToHash } from "@/pages/settings/hooks/use-permissions-matrix"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"
import { Switch } from "@/components/ui/switch"
import { PermissionsMatrix } from "@/pages/settings/components/permissions-matrix"

export function ApiKeyEditSheet({
  apiKey,
  open,
  onOpenChange,
}: {
  apiKey: ApiKeyType | null
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const { perms: editPerms, togglePerm, replace: replacePerms } = usePermissionsMatrix()
  const [name, setName] = useState("")
  const [active, setActive] = useState(true)

  useEffect(() => {
    if (apiKey && open) {
      setName(apiKey.name)
      setActive(apiKey.active)
      replacePerms(apiKey.permissions)
    }
  }, [apiKey, open, replacePerms])

  if (!apiKey) return null

  const handleSave = () => {
    router.patch(apiKeyPath(apiKey.id), {
      name,
      active,
      permissions: permsToHash(editPerms),
    }, {
      onSuccess: () => onOpenChange(false),
    })
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Edit API Key</SheetTitle>
          <SheetDescription>
            Update settings and permissions for <span className="font-medium">{apiKey.name}</span>
          </SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-6 px-6 pb-6">
          <div className="flex flex-col gap-2">
            <Label htmlFor="edit-key-name">Name</Label>
            <Input id="edit-key-name" value={name} onChange={(e) => setName(e.target.value)} />
          </div>

          <div className="flex flex-col gap-2">
            <Label>Token</Label>
            <code className="rounded-md bg-muted px-3 py-2 font-mono text-sm text-muted-foreground">
              {apiKey.tokenPrefix}...
            </code>
            <p className="text-xs text-muted-foreground">
              The full token cannot be revealed. Create a new key if you've lost it.
            </p>
          </div>

          <div className="flex items-center justify-between rounded-lg border p-3">
            <div>
              <Label htmlFor="edit-key-active" className="text-sm font-medium">Active</Label>
              <p className="text-xs text-muted-foreground">
                Inactive keys cannot authenticate API requests
              </p>
            </div>
            <Switch id="edit-key-active" checked={active} onCheckedChange={setActive} />
          </div>

          <Separator />

          <div className="flex flex-col gap-3">
            <Label className="text-sm font-medium">Permissions</Label>
            <PermissionsMatrix perms={editPerms} onToggle={togglePerm} />
          </div>

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button onClick={handleSave}>
              Save Changes
            </Button>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}
