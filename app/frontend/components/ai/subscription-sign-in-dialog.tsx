import { useEffect, useRef, useState, type ChangeEvent, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import type { CancelToken, Page } from "@inertiajs/core"
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
import { AI_SUBSCRIPTION_SIGN_IN_PROPS, SUBSCRIPTION_CALLBACK_ADDRESS_PARAM } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import {
  advanceSubscriptionSignInPath,
  finishSubscriptionSignInPath,
  subscriptionSignInPath,
} from "@/lib/routes"
import type { FlashData } from "@/types"
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
  // The address went through and the proxy is finishing the sign-in, so the same code is never handed back twice.
  const [handedBackFor, setHandedBackFor] = useState<string | null>(null)
  // A request of the person's own (handing back or cancelling) is never cut short by a check, and checks never overlap.
  const busy = useRef(false)
  const asking = useRef(false)
  const check = useRef<CancelToken | null>(null)
  const signInId = signIn?.id

  useEffect(() => {
    if (!signInId) {
      return
    }
    const timer = window.setInterval(() => {
      if (busy.current || asking.current) {
        return
      }
      asking.current = true
      router.post(advanceSubscriptionSignInPath(signInId), {}, {
        ...QUIET_VISIT,
        async: true,
        onCancelToken: (token) => {
          check.current = token
        },
        onFinish: () => {
          asking.current = false
          check.current = null
        },
      })
    }, ASK_EVERY_MS)
    return () => {
      window.clearInterval(timer)
      check.current?.cancel()
    }
  }, [signInId])

  // A check answered before the person's own request would land after it and show the sign-in it had seen, so it is
  // dropped first.
  function dropCheck() {
    check.current?.cancel()
  }

  function idle() {
    busy.current = false
  }

  function cancel() {
    if (!signIn) {
      return
    }
    busy.current = true
    dropCheck()
    router.delete(subscriptionSignInPath(signIn.id), { ...QUIET_VISIT, onFinish: idle })
  }

  function changeAddress(event: ChangeEvent<HTMLInputElement>) {
    setAddress(event.target.value)
  }

  function finished() {
    idle()
    setSending(false)
    setAddress("")
  }

  function handedBack(page: Page) {
    const flash = page.flash as FlashData | undefined
    if (!flash?.alert && signIn) {
      setHandedBackFor(signIn.id)
    }
  }

  function handBack(event: FormEvent) {
    event.preventDefault()
    if (!signIn) {
      return
    }
    busy.current = true
    dropCheck()
    setSending(true)
    router.post(
      finishSubscriptionSignInPath(signIn.id),
      { [SUBSCRIPTION_CALLBACK_ADDRESS_PARAM]: address },
      { ...QUIET_VISIT, onSuccess: handedBack, onFinish: finished },
    )
  }

  function copyCode() {
    if (!signIn?.userCode) {
      return
    }
    void navigator.clipboard.writeText(signIn.userCode).then(() => setCopied(true))
  }

  const finishing = Boolean(signIn) && handedBackFor === signIn?.id
  const title = signIn ?`${signIn.reconnecting ? "Sign in again to" : "Connect"} ${signIn.name}` : ""

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
              {finishing ? (
                <p className="flex items-center gap-2 text-sm text-muted-foreground">
                  <IconLoader2 className="size-4 animate-spin" />
                  Finishing the sign-in. This closes by itself once it has.
                </p>
              ) : (
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
              )}
            </div>
            <DialogFooter>
              <DialogClose asChild>
                <Button type="button" variant="outline">Cancel</Button>
              </DialogClose>
              {!finishing && (
                <Button type="submit" disabled={sending || address.trim() === ""}>
                  {sending ? "Connecting" : "Connect"}
                </Button>
              )}
            </DialogFooter>
          </form>
        ) : null}
      </DialogContent>
    </Dialog>
  )
}
