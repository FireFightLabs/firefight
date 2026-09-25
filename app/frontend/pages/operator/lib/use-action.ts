import { router } from "@inertiajs/react"
import { useState } from "react"

// Posts an operator action and reports busy until the server answers, so buttons can be disabled and a double click
// does not send the action twice.
export function useAction() {
  const [busy, setBusy] = useState(false)

  function start() {
    setBusy(true)
  }

  function finish() {
    setBusy(false)
  }

  function post(url: string) {
    router.post(url, {}, { preserveScroll: true, onStart: start, onFinish: finish })
  }

  return { busy, post }
}
