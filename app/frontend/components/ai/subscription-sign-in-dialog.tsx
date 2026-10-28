import { useEffect, useState, type ChangeEvent, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import { IconCopy, IconExternalLink, IconLoader2 } from "@tabler/icons-react"

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
import { AI_SUBSCRIPTION_SIGN_IN_PROPS } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import {
  advanceSubscriptionSignInPath,
  finishSubscriptionSignInPath,
  subscriptionSignInPath,
} from "@/lib/routes"
import type { SubscriptionSignIn } from "@/types/serializers"

const SIGN_IN_PROPS: string[] = Object.values(AI_SUBSCRIPTION_SIGN_IN_PROPS)
const ASK_EVERY_MS = 3000
const QUIET_VISIT = { preserveScroll: true, preserveState: true, showProgress: false, only: SIGN_IN_PROPS }

// A sign-in to a subscription the person has waiting. A device sign-in shows the code to enter on the provider's page,
// and one that sends the browser back to the person's own computer asks for that address. Either way the page asks
// every few seconds whether it finished, and the dialog closes once it has.
export function SubscriptionSignInDialog({ signIn }: { signIn: SubscriptionSignIn | null }) {
  const [address, setAddress] = useState("")
  const [sending, setSending] = useState(false)
  const [copied, setCopied] = useState(false)
  const signInId = signIn?.id

  useEffect(() => {
    if (!signInId) {
      return
    }
    const timer = window.setInterval(() => {
      router.post(advanceSubscriptionSignInPath(signInId), {}, QUIET_VISIT)
    }, ASK_EVERY_MS)
    return () => window.clearInterval(timer)
  }, [signInId])

  function cancel() {
    if (!signIn) {
      return
    }
    router.delete(subscriptionSignInPath(signIn.id), QUIET_VISIT)
  }

  function changeAddress(event: ChangeEvent<HTMLInputElement>) {
    setAddress(event.target.value)
  }

  function finished() {
    setSending(false)
    setAddress("")
  }

  function handBack(event: FormEvent) {
    event.preventDefault()
    if (!signIn) {
      return
    }
    setSending(true)
    router.post(finishSubscriptionSignInPath(signIn.id), { address }, { ...QUIET_VISIT, onFinish: finished })
  }

  function copyCode() {
    if (!signIn?.userCode) {
      return
    }
    void navigator.clipboard.writeText(signIn.userCode).then(() => setCopied(true))
  }

  const title = signIn ? `${signIn.reconnecting ? "Sign in again to" : "Connect"} ${signIn.name}` : ""

  return (
    <Dialog open={Boolean(signIn)} onOpenChange={whenClosed(cancel)}>
      <DialogContent className="sm:max-w-lg">
        {signIn?.device ? (
          <>
            <DialogHeader>
              <DialogTitle>{title}</DialogTitle>
              <DialogDescription>
                Open {signIn.host}, sign in with the account that has the subscription, and enter this code when it asks.
              </DialogDescription>
            </DialogHeader>
            <div className="flex flex-col items-start gap-4 py-4">
              <div className="flex items-center gap-2">
                <span className="rounded-md border bg-muted px-3 py-2 font-mono text-lg tracking-widest">{signIn.userCode}</span>
                <Button type="button" variant="outline" size="sm" onClick={copyCode}>
                  <IconCopy className="size-4" />
                  {copied ? "Copied" : "Copy"}
                </Button>
              </div>
              <Button asChild size="sm">
                <a href={signIn.url} target="_blank" rel="noreferrer">
                  <IconExternalLink className="size-4" />
                  Open {signIn.host}
                </a>
              </Button>
              <p className="flex items-center gap-2 text-sm text-muted-foreground">
                <IconLoader2 className="size-4 animate-spin" />
                Waiting for you to finish signing in. This closes by itself once you have.
              </p>
            </div>
            <DialogFooter>
              <DialogClose asChild>
                <Button type="button" variant="outline">Cancel</Button>
              </DialogClose>
            </DialogFooter>
          </>
        ) : signIn ? (
          <form onSubmit={handBack}>
            <DialogHeader>
              <DialogTitle>{title}</DialogTitle>
              <DialogDescription>
                Sign in on {signIn.host} with the account that has the subscription. Afterwards your browser opens an address
                starting with http://localhost that does not load. That is expected. Copy the whole address from the address
                bar and paste it here.
              </DialogDescription>
            </DialogHeader>
            <div className="flex flex-col gap-4 py-4">
              <Button asChild size="sm" className="self-start">
                <a href={signIn.url} target="_blank" rel="noreferrer">
                  <IconExternalLink className="size-4" />
                  Sign in on {signIn.host}
                </a>
              </Button>
              <div className="flex flex-col gap-2">
                <Label htmlFor={`subscription-address-${signIn.id}`}>Address your browser opened</Label>
                <Input
                  id={`subscription-address-${signIn.id}`}
                  value={address}
                  onChange={changeAddress}
                  placeholder="http://localhost..."
                  autoComplete="off"
                />
              </div>
            </div>
            <DialogFooter>
              <DialogClose asChild>
                <Button type="button" variant="outline">Cancel</Button>
              </DialogClose>
              <Button type="submit" disabled={sending || address.trim() === ""}>
                {sending ? "Connecting" : "Connect"}
              </Button>
            </DialogFooter>
          </form>
        ) : null}
      </DialogContent>
    </Dialog>
  )
}
