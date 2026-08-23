import { createInertiaApp, type ResolvedComponent } from '@inertiajs/react'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'

void createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob<ResolvedComponent>('../pages/**/*.tsx', {
      eager: true,
    })
    // Pages contributed by the proprietary cloud engine. The directory is
    // populated by the cloud build and absent on self-hosted builds, where
    // the glob matches nothing there.
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
  // Only Inertia pages carry the #app root, so a missing one means this
  // entrypoint was loaded on a page that does not use Inertia.
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
