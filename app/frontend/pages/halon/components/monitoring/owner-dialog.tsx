import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"

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
import { whenClosed } from "@/lib/handlers"
import { changeOwnerInvestigationCheckPath } from "@/lib/routes"
import type { InvestigationCheck } from "@/types/serializers"
import type { CheckMember } from "@/pages/halon/components/monitoring/types"

// Picks the member a check runs in the name of. The server says it, and resumes a paused check.
export function OwnerDialog({
  check,
  members,
  onClose,
}: {
  check: InvestigationCheck | null
  members: CheckMember[]
  onClose: () => void
}) {
  const [ownerId, setOwnerId] = useState("")
  const [processing, setProcessing] = useState(false)
  const [lastCheckId, setLastCheckId] = useState<string | null>(null)
  if (check && check.id !== lastCheckId) {
    setLastCheckId(check.id)
    setOwnerId(members.some((member) => member.id === check.ownerId) ? check.ownerId ?? "" : "")
  }

  function finish() {
    setProcessing(false)
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    if (!check || !ownerId) {
      return
    }
    setProcessing(true)
    router.patch(changeOwnerInvestigationCheckPath(check.id), { owner_id: ownerId }, { preserveScroll: true, onSuccess: onClose, onFinish: finish })
  }

  return (
    <Dialog open={Boolean(check)} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Change owner</DialogTitle>
            <DialogDescription>
              {check?.name} runs in its owner&apos;s name, so it reads only what they can. A paused check runs again once it has an owner.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-2 py-4">
            <Label htmlFor="check-owner">Owner</Label>
            <Select value={ownerId} onValueChange={setOwnerId}>
              <SelectTrigger id="check-owner" className="w-full">
                <SelectValue placeholder="Choose a member" />
              </SelectTrigger>
              <SelectContent>
                {members.map((member) => (
                  <SelectItem key={member.id} value={member.id}>{member.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing || !ownerId}>Change owner</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
