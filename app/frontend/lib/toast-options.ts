import type { ToasterProps } from "sonner"

// Sonner's own stylesheet is unlayered, so these need the important modifier to win over it.
// Each toast sits on its feedback tint with a 2px edge and icon in the accent, text stays primary.
export const TOAST_OPTIONS: ToasterProps["toastOptions"] = {
  classNames: {
    toast: "!border-border !text-fg-primary !shadow-popover",
    description: "!text-fg-body",
    success: "!border-l-2 !border-l-success !bg-success-tint [&_[data-icon]]:!text-success",
    error: "!border-l-2 !border-l-error !bg-error-tint [&_[data-icon]]:!text-error",
    warning: "!border-l-2 !border-l-warning !bg-warning-tint [&_[data-icon]]:!text-warning",
    info: "!border-l-2 !border-l-info !bg-info-tint [&_[data-icon]]:!text-info",
  },
}
