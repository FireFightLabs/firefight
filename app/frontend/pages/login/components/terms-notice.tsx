export function TermsNotice() {
  return (
    <div className="mt-10 border-t border-primary/25 pt-6">
      <p className="text-xs leading-relaxed text-muted-foreground">
        By continuing, you agree to our
      </p>
      <p className="mt-1 text-xs leading-relaxed">
        <a
          href="https://firefight.app/terms"
          target="_blank"
          rel="noopener noreferrer"
          className="font-semibold text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
        >
          Terms
        </a>
        <span className="text-muted-foreground"> and </span>
        <a
          href="https://firefight.app/privacy"
          target="_blank"
          rel="noopener noreferrer"
          className="font-semibold text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
        >
          Privacy Policy
        </a>
      </p>
    </div>
  );
}
