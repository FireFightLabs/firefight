import { useState, type ChangeEvent, type FormEvent } from "react"
import { useForm } from "@inertiajs/react"
import type { HttpResponse } from "@inertiajs/core"
import { IconMail } from "@tabler/icons-react"

import { workspaceInvitationsPath } from "@/lib/routes"
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
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Blocked } from "@/pages/settings/components/blocked-tooltip"

const TOO_MANY_STATUS = 429
const TOO_MANY_MESSAGE = "Too many invitations were sent from this network. Try again in an hour."

export function InviteDialog({ unavailableReason, days }: { unavailableReason: string | null; days: number }) {
  const [open, setOpen] = useState(false)
  const form = useForm({ emails: "" })

  function changeEmails(event: ChangeEvent<HTMLTextAreaElement>) {
    form.setData("emails", event.target.value)
  }

  function finish() {
    setOpen(false)
    form.reset()
  }

  // A throttled request answers with a plain page, which would otherwise open over the dialog.
  function handleHttpException(response: HttpResponse) {
    if (response.status !== TOO_MANY_STATUS) {
      return
    }
    form.setError("emails", [TOO_MANY_MESSAGE])
    return false
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    form.post(workspaceInvitationsPath(), { preserveScroll: true, onSuccess: finish, onHttpException: handleHttpException })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <Blocked reason={unavailableReason ?? undefined}>
        <DialogTrigger asChild>
          <Button size="sm" disabled={Boolean(unavailableReason)}>
            <IconMail className="size-4" />
            Invite people
          </Button>
        </DialogTrigger>
      </Blocked>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Invite people</DialogTitle>
            <DialogDescription>
              Each person gets an email with a link that signs them in and adds them as a member. The link works for{" "}
              {days} days.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-2 py-4">
            <Label htmlFor="invite-emails">Email addresses</Label>
            <Textarea
              id="invite-emails"
              rows={4}
              placeholder="ana@company.com, sam@company.com"
              value={form.data.emails}
              onChange={changeEmails}
              aria-invalid={form.errors.emails ? true : undefined}
            />
            {form.errors.emails ? (
              <p className="text-xs text-destructive">{form.errors.emails}</p>
            ) : (
              <p className="text-xs text-muted-foreground">Separate addresses with commas or new lines.</p>
            )}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              Send invitations
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
