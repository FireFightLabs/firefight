import { isValidElement, type ReactNode, useEffect, useState } from "react"

import { fenceLanguage, highlight } from "@/lib/code-highlight"

export interface Fenced {
  code: string
  language: string | undefined
}

// The text and the language of the code react-markdown put inside a fenced block's pre.
export function fenced(children: ReactNode): Fenced | null {
  if (!isValidElement<{ className?: string; children?: ReactNode }>(children)) {
    return null
  }
  const text = children.props.children
  return typeof text === "string" ? { code: text.replace(/\n$/, ""), language: fenceLanguage(children.props.className) } : null
}

// The block highlighted once its language has loaded, plain until then and whenever it cannot be.
export function useHighlighted(block: Fenced | null): string | null {
  const [ shown, setShown ] = useState<{ code: string; html: string | null } | null>(null)
  const code = block?.code
  const language = block?.language

  useEffect(() => {
    if (code === undefined) {
      return
    }
    let current = true
    highlight(code, language).then((html) => {
      if (current) {
        setShown({ code, html })
      }
    }).catch(() => undefined)
    return () => {
      current = false
    }
  }, [ code, language ])

  return shown && shown.code === code ? shown.html : null
}
