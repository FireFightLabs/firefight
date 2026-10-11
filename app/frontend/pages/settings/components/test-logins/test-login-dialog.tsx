import { useState, type ChangeEvent, type FormEvent } from "react"
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
import { testLoginPath, testLoginsPath } from "@/lib/routes"
import type { TestLogin } from "@/types/serializers"

type Field = "name" | "site_url" | "login_url" | "username" | "password"

// Owns both adding and editing, so the page renders one dialog. The password is never sent to the page, so editing
// starts it empty and leaving it empty keeps the one saved.
export function TestLoginDialog({
  login,
  open,
  onOpenChange,
}: {
  login?: TestLogin
  open?: boolean
  onOpenChange?: (open: boolean) => void
}) {
  const [uncontrolled, setUncontrolled] = useState(false)
  const isOpen = open ?? uncontrolled
  const setOpen = onOpenChange ?? setUncontrolled
  const editing = Boolean(login)

  const { data, setData, post, patch, processing, errors, reset, clearErrors } = useForm<Record<Field, string>>({
    name: login?.name ?? "",
    site_url: login?.siteUrl ?? "",
    login_url: login?.loginUrl ?? "",
    username: login?.username ?? "",
    password: "",
  })

  function close() {
    setOpen(false)
    clearErrors()
    if (!editing) {
      reset()
    }
  }

  function changeOpen(next: boolean) {
    if (next) {
      setOpen(true)
    } else {
      close()
    }
  }

  function changeField(field: Field) {
    return (event: ChangeEvent<HTMLInputElement>) => setData(field, event.target.value)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    const options = { preserveScroll: true, onSuccess: close }

    if (login) {
      patch(testLoginPath(login.id), options)
    } else {
      post(testLoginsPath(), options)
    }
  }

  const ready = data.site_url.trim() !== "" && data.username.trim() !== "" && (editing || data.password !== "")

  return (
    <Dialog open={isOpen} onOpenChange={changeOpen}>
      {!editing && (
        <DialogTrigger asChild>
          <Button size="sm" className="gap-1.5">
            <IconPlus className="size-4" />
            New test login
          </Button>
        </DialogTrigger>
      )}
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{editing ? `Edit ${login?.name}` : "New test login"}</DialogTitle>
            <DialogDescription>
              Use an account made for testing, never a real person&apos;s. Halon&apos;s browser signs in with it, and the
              password never reaches Halon.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="test-login-site">Site address</Label>
              <Input
                id="test-login-site"
                value={data.site_url}
                onChange={changeField("site_url")}
                placeholder="https://shop.example.com"
                autoComplete="off"
              />
              {errors.site_url && <p className="text-xs text-destructive">{errors.site_url}</p>}
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="test-login-page">Login page (optional)</Label>
              <Input
                id="test-login-page"
                value={data.login_url}
                onChange={changeField("login_url")}
                placeholder="https://shop.example.com/login"
                autoComplete="off"
              />
              <p className="text-xs text-muted-foreground">Where the login form is, when it is not the site address.</p>
              {errors.login_url && <p className="text-xs text-destructive">{errors.login_url}</p>}
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="test-login-username">Username</Label>
              <Input
                id="test-login-username"
                value={data.username}
                onChange={changeField("username")}
                placeholder="halon-test@example.com"
                autoComplete="off"
              />
              {errors.username && <p className="text-xs text-destructive">{errors.username}</p>}
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="test-login-password">Password</Label>
              <Input
                id="test-login-password"
                type="password"
                value={data.password}
                onChange={changeField("password")}
                autoComplete="new-password"
              />
              <p className="text-xs text-muted-foreground">
                {editing
                  ? `${login?.passwordHint}. Leave this empty to keep it.`
                  : "It is never shown again."}
              </p>
              {errors.password && <p className="text-xs text-destructive">{errors.password}</p>}
            </div>

            <div className="flex flex-col gap-1.5">
              <Label htmlFor="test-login-name">Name (optional)</Label>
              <Input
                id="test-login-name"
                value={data.name}
                onChange={changeField("name")}
                placeholder="The site address when left empty"
              />
              {errors.name && <p className="text-xs text-destructive">{errors.name}</p>}
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={close}>
              Never mind
            </Button>
            <Button type="submit" disabled={processing || !ready}>
              {editing ? "Save" : "Save test login"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
