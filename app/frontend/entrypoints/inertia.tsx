import { createInertiaApp, type ResolvedComponent } from '@inertiajs/react'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'

import { reloadDroppedDeferredProps } from '@/lib/deferred-props'
import type { ErrorReportingSettings } from '@/types'

// Sentry's code is fetched only when the deployment gave the page a DSN, so a page without one never loads it.
function reportErrors(settings: ErrorReportingSettings | null | undefined) {
  if (!settings) {
    return
  }

  void import('@/lib/error-reporting').then(({ startErrorReporting }) => {
    startErrorReporting(settings)
  })
}

void createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob<ResolvedComponent>('../pages/**/*.tsx', {
      eager: true,
    })
    // Cloud engine pages. The directory only exists in cloud builds, so the
    // glob matches nothing on self-hosted.
    const cloudPages = import.meta.glob<ResolvedComponent>('../cloud_pages/**/*.tsx', {
      eager: true,
    })
    const page = pages[`../pages/${name}.tsx`] ?? cloudPages[`../cloud_pages/${name}.tsx`]
    if (!page) {
      console.error(`Missing Inertia page component: '${name}.tsx'`)
    }

    return page
  },

  setup({ el, App, props }) {
    reportErrors(props.initialPage.props.errorReporting)
    reloadDroppedDeferredProps()
    createRoot(el).render(
      <StrictMode>
        <App {...props} />
      </StrictMode>
    )
  },

  defaults: {
    form: {
      forceIndicesArrayFormatInFormData: true,
    },
  },
}).catch((error) => {
  // Only Inertia pages carry the #app root, so a missing one means this loaded
  // on a page that does not use Inertia.
  if (document.getElementById("app")) {
    throw error
  } else {
    console.error(
      "Missing root element.\n\n" +
      "If you see this error, it probably means you loaded Inertia.js on non-Inertia pages.\n" +
      'Consider moving <%= vite_typescript_tag "inertia.tsx" %> to the Inertia-specific layout instead.',
    )
  }
})
