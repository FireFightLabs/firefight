import { useCallback, useState } from "react"

export function permsToHash(perms: Record<string, Set<string>>): Record<string, string[]> {
  const result: Record<string, string[]> = {}
  for (const [resource, actions] of Object.entries(perms)) {
    if (actions.size > 0) {
      result[resource] = [...actions]
    }
  }
  return result
}

export function usePermissionsMatrix(initial: Record<string, string[]> = {}) {
  const [perms, setPerms] = useState<Record<string, Set<string>>>(() =>
    Object.fromEntries(Object.entries(initial).map(([k, v]) => [k, new Set(v)]))
  )

  const togglePerm = useCallback((resource: string, action: string) => {
    setPerms((prev) => {
      const next = { ...prev }
      const current = new Set(prev[resource] || [])
      if (current.has(action)) {
        current.delete(action)
      }
      else {
        current.add(action)
      }
      next[resource] = current
      return next
    })
  }, [])

  const replace = useCallback((h: Record<string, string[]>) => {
    setPerms(Object.fromEntries(Object.entries(h).map(([k, v]) => [k, new Set(v)])))
  }, [])

  const reset = useCallback(() => setPerms({}), [])

  return { perms, togglePerm, replace, reset }
}
