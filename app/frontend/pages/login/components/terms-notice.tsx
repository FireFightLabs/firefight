export function TermsNotice() {
  return (
    <div className="mt-10 border-t border-border pt-6">
      <p className="text-xs leading-relaxed text-fg-muted">
        By continuing, you agree to our
      </p>
      <p className="mt-1 text-xs leading-relaxed">
        <a
          href="https://firefight.app/terms"
          target="_blank"
          rel="noopener noreferrer"
          className="font-semibold text-fg-primary underline decoration-border-control underline-offset-[3px] transition-colors duration-120 hover:decoration-fg-primary"
        >
          Terms
        </a>
        <span className="text-fg-muted"> and </span>
        <a
          href="https://firefight.app/privacy"
          target="_blank"
          rel="noopener noreferrer"
          className="font-semibold text-fg-primary underline decoration-border-control underline-offset-[3px] transition-colors duration-120 hover:decoration-fg-primary"
        >
          Privacy Policy
        </a>
      </p>
    </div>
  );
}
