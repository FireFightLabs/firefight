import type { ToasterProps } from "sonner"

// Sonner's own stylesheet is unlayered, so these need the important modifier to win over it.
// Each toast sits on its feedback tint with a 2px edge bar and icon in the accent, text stays primary.
export const TOAST_OPTIONS: ToasterProps["toastOptions"] = {
  classNames: {
    toast: "!border-border !text-fg-primary !shadow-popover",
    description: "!text-fg-body",
    success: "!edge-bar [--edge-bar-inset:10px] [--edge-bar:var(--success)] !bg-success-tint [&_[data-icon]]:!text-success",
    error: "!edge-bar [--edge-bar-inset:10px] [--edge-bar:var(--error)] !bg-error-tint [&_[data-icon]]:!text-error",
    warning: "!edge-bar [--edge-bar-inset:10px] [--edge-bar:var(--warning)] !bg-warning-tint [&_[data-icon]]:!text-warning",
    info: "!edge-bar [--edge-bar-inset:10px] [--edge-bar:var(--info)] !bg-info-tint [&_[data-icon]]:!text-info",
  },
}
