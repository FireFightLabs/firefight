import { IconMoon, IconSun } from "@tabler/icons-react"
import * as React from "react"

import { Button } from "@/components/ui/button"

export function ThemeToggle() {
  const [dark, setDark] = React.useState(() => {
    if (typeof window === "undefined") return false
    return document.documentElement.classList.contains("dark")
  })

  const toggle = () => {
    const next = !dark
    setDark(next)
    document.documentElement.classList.toggle("dark", next)
    localStorage.setItem("theme", next ? "dark" : "light")
  }

  React.useEffect(() => {
    const saved = localStorage.getItem("theme")
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const shouldBeDark = saved ? saved === "dark" : prefersDark
    setDark(shouldBeDark)
    document.documentElement.classList.toggle("dark", shouldBeDark)
  }, [])

  return (
    <Button variant="ghost" size="icon" onClick={toggle} className="size-8">
      {dark ? <IconSun className="size-4" /> : <IconMoon className="size-4" />}
      <span className="sr-only">Toggle theme</span>
    </Button>
  )
}
