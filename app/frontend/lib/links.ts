const WEB_PROTOCOLS = [ "http:", "https:" ]
const NEW_TAB_REL = "noopener noreferrer"

interface NewTabAttributes {
  target?: "_blank"
  rel?: string
}

// A link that leaves the dashboard opens beside it, so following a source never loses the page it came from.
export function isExternalHref(href: string | undefined): boolean {
  if (!href) {
    return false
  }
  let url: URL
  try {
    url = new URL(href, window.location.href)
  } catch {
    return false
  }
  return WEB_PROTOCOLS.includes(url.protocol) && url.origin !== window.location.origin
}

export function newTabAttributes(href: string | undefined): NewTabAttributes {
  if (!isExternalHref(href)) {
    return {}
  }
  return { target: "_blank", rel: NEW_TAB_REL }
}

// For stored HTML the dashboard renders as is. Links inside the dashboard keep whatever the HTML gave them.
export function withExternalLinksInNewTab(html: string): string {
  const parsed = new DOMParser().parseFromString(html, "text/html")
  parsed.querySelectorAll<HTMLAnchorElement>("a[href]").forEach((anchor) => {
    if (isExternalHref(anchor.getAttribute("href") ?? undefined)) {
      anchor.setAttribute("target", "_blank")
      anchor.setAttribute("rel", NEW_TAB_REL)
    }
  })
  return parsed.body.innerHTML
}
