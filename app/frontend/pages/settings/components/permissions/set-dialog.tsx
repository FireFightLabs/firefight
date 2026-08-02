import { useEffect, useState } from "react"
import { router } from "@inertiajs/react"

import { abilityRolesPath } from "@/lib/routes"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

export function SetDialog({ open, onDismiss }: { open: boolean; onDismiss: () => void }) {
  const [name, setName] = useState("")

  useEffect(() => {
    if (open) {
      setName("")
    }
  }, [open])

  function submit() {
    if (!name.trim()) {
      return
    }
    router.post(abilityRolesPath(), { name: name.trim() }, { onFinish: onDismiss })
  }

  return (
    <Dialog open={open} onOpenChange={(next) => { if (!next) { onDismiss() } }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>New permission set</DialogTitle>
          <DialogDescription>
            Name it for what it lets someone do. You pick the abilities next, and grant the set as one.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-1.5">
          <Label htmlFor="set-name">Name</Label>
          <Input
            id="set-name"
            autoFocus
            value={name}
            onChange={(event) => setName(event.target.value)}
            onKeyDown={(event) => { if (event.key === "Enter") { submit() } }}
            placeholder="e.g. Database read-only"
          />
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onDismiss}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={!name.trim()}>
            Create set
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
