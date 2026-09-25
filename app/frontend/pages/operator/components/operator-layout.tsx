import { Head, Link, router, usePage } from "@inertiajs/react"
import {
  IconArrowLeft,
  IconFlame,
  IconHierarchy2,
  IconLayoutDashboard,
  IconLogout,
  IconMessages,
  IconSearch,
  IconSparkles,
  IconStack2,
  type Icon,
} from "@tabler/icons-react"
import { useState, type FormEvent, type ReactNode } from "react"

import { FireFightLogo } from "@/components/fire-fight-logo"
import { FlashToaster } from "@/components/flash-toaster"
import { Toaster } from "@/components/ui/sonner"
import { Input } from "@/components/ui/input"
import { TooltipProvider } from "@/components/ui/tooltip"
import {
  dashboardPath,
  logoutPath,
  operatorFindPath,
  operatorHalonChatsPath,
  operatorHalonPath,
  operatorIncidentsPath,
  operatorJobsPath,
  operatorRootPath,
  operatorWorkflowsPath,
} from "@/lib/routes"
import type { OperatorPageProps } from "@/pages/operator/types"

interface NavItem {
  title: string
  href: string
  icon: Icon
  // Flightdeck is not an Inertia page, so its link does a full page load.
  external?: boolean
  // Every console path starts with the overview's path, so the overview only matches exactly.
  exact?: boolean
  // Paths under this item's path that belong to another item.
  except?: string[]
}

interface NavSection {
  title: string
  items: NavItem[]
}

const SECTIONS: NavSection[] = [
  { title: "Watch", items: [{ title: "Overview", href: operatorRootPath(), icon: IconLayoutDashboard, exact: true }] },

  {
    title: "Processes",
    items: [
      { title: "Incidents", href: operatorIncidentsPath(), icon: IconFlame },
      { title: "Workflows", href: operatorWorkflowsPath(), icon: IconHierarchy2 },
      { title: "Jobs", href: operatorJobsPath(), icon: IconStack2, external: true },
    ],
  },
  {
    title: "Halon",
    items: [
      { title: "Runs and health", href: operatorHalonPath(), icon: IconSparkles, except: [operatorHalonChatsPath()] },
      { title: "Chats", href: operatorHalonChatsPath(), icon: IconMessages },
    ],
  },
]

function isActive(item: NavItem, url: string): boolean {
  const path = url.split("?")[0]
  if (item.except?.some((prefix) => path.startsWith(prefix))) {
    return false
  }
  return item.exact ? path === item.href : path.startsWith(item.href)
}

function NavLink({ item, active, badge }: { item: NavItem; active: boolean; badge?: number }) {
  const ItemIcon = item.icon
  const className = `relative flex h-9 items-center gap-3 rounded-lg px-3 text-sm transition-colors ${
    active ? "bg-card text-foreground" : "text-muted-foreground hover:bg-card/60 hover:text-foreground"
  }`
  const content = (
    <>
      {active && <span aria-hidden className="absolute top-2 bottom-2 -left-3 w-0.5 rounded-full bg-primary" />}
      <ItemIcon className={`size-4 ${active ? "text-primary" : ""}`} stroke={1.6} />
      {item.title}
      {badge ? (
        <span className="ml-auto rounded-full bg-rose-500/15 px-1.5 font-mono text-[11px] text-rose-600 dark:text-rose-400">{badge}</span>
      ) : null}
    </>
  )

  return item.external ? (
    <a href={item.href} className={className}>{content}</a>
  ) : (
    <Link href={item.href} className={className}>{content}</Link>
  )
}

// Find box. Submits a pasted id or incident number to the find page, which opens a single match.
function FindBox() {
  const [query, setQuery] = useState("")

  function change(event: React.ChangeEvent<HTMLInputElement>) {
    setQuery(event.target.value)
  }

  function find(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const pasted = query.trim()
    if (!pasted) {
      return
    }
    router.get(operatorFindPath({ q: pasted }))
  }

  return (
    <form role="search" onSubmit={find} className="border-b border-border px-3 py-3">
      <label className="relative block">
        <span className="sr-only">Find by id or incident number</span>
        <IconSearch className="text-muted-foreground pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2" />
        <Input
          id="operator-find"
          value={query}
          onChange={change}
          placeholder="Find an id or INC-042"
          autoComplete="off"
          spellCheck={false}
          className="h-8 pl-8 font-mono text-xs"
        />
      </label>
    </form>
  )
}

function signOut() {
  router.delete(logoutPath())
}

// The console layout, a sidebar with sections, the signed in operator, and a link back to Firefight. It has no
// workspace selector, since operators see all workspaces.
export function OperatorLayout({ title, children }: { title: string; children: ReactNode }) {
  const page = usePage<OperatorPageProps>()
  const { operator, attention } = page.props

  return (
    <TooltipProvider>
      <Head title={`${title} · Operator`} />
      <div className="flex min-h-svh bg-background text-foreground">
        <aside className="sticky top-0 flex h-svh w-62 shrink-0 flex-col border-r border-border">
          <div className="flex h-16 items-center gap-3 border-b border-border px-5">
            <FireFightLogo className="size-7" />
            <span className="font-semibold">Firefight</span>
            <span className="rounded-full border border-primary/30 bg-primary/5 px-2 py-0.5 text-[9.5px] font-medium tracking-[0.14em] text-primary uppercase">
              Operator
            </span>
          </div>
          <FindBox />
          <nav aria-label="Operator console" className="flex flex-1 flex-col gap-6 overflow-y-auto px-3 py-6">
            {SECTIONS.map((section) => (
              <div key={section.title} className="flex flex-col gap-1">
                <p className="px-3 pb-2 text-[10.5px] font-medium tracking-[0.18em] text-muted-foreground/75 uppercase">{section.title}</p>
                {section.items.map((item) => (
                  <NavLink key={item.title} item={item} active={isActive(item, page.url)} badge={item.href === operatorRootPath() ? attention : undefined} />
                ))}
              </div>
            ))}
          </nav>
          <div className="flex flex-col gap-1 border-t border-border p-3">
            <div className="px-3 py-2">
              <p className="truncate text-sm font-medium">{operator?.name}</p>
              <p className="truncate text-xs text-muted-foreground">{operator?.email}</p>
            </div>
            <Link href={dashboardPath()} className="flex h-9 items-center gap-3 rounded-lg px-3 text-sm text-muted-foreground hover:bg-card/60 hover:text-foreground">
              <IconArrowLeft className="size-4" stroke={1.6} />
              Back to Firefight
            </Link>
            <button type="button" onClick={signOut} className="flex h-9 items-center gap-3 rounded-lg px-3 text-left text-sm text-muted-foreground hover:bg-card/60 hover:text-foreground">
              <IconLogout className="size-4" stroke={1.6} />
              Sign out
            </button>
          </div>
        </aside>
        <main className="min-w-0 flex-1 px-9 py-8">{children}</main>
      </div>
      <Toaster />
      <FlashToaster />
    </TooltipProvider>
  )
}
