import { Head } from "@inertiajs/react";
import { SlackAuthButton } from "@/modules/auth/components/slack-auth-button";

export default function Login() {
  return (
    <>
      <Head title="Sign in to Firefight" />
      <div className="relative flex min-h-svh flex-col bg-background text-foreground">
        {/* Ambient grid — sits in the background, barely visible. Signals craft without shouting. */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(10,30,46,0.035)_1px,transparent_1px),linear-gradient(to_bottom,rgba(10,30,46,0.035)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
        />

        <main className="relative flex flex-1 items-center justify-center px-6 py-12">
          <div className="w-full max-w-[420px]">
            {/* Card — gives the content weight and a deliberate anchor on the page.
                Text stays left-aligned inside (editorial feel); card is centered in the viewport. */}
            <div className="relative rounded-xl border border-border bg-card px-8 py-10 text-center shadow-[0_1px_0_0_rgba(10,30,46,0.02),0_1px_2px_0_rgba(10,30,46,0.04),0_8px_24px_-8px_rgba(10,30,46,0.08)] sm:px-10 sm:py-12">
              <div className="mb-8 space-y-2">
                <h1 className="text-[1.75rem] font-medium leading-[1.15] tracking-[-0.02em] text-foreground">
                  Sign in
                </h1>
                <p className="mx-auto max-w-[32ch] text-[0.9375rem] leading-relaxed text-muted-foreground">
                  Connect your Slack workspace to get started. We'll create your
                  workspace on first sign-in.
                </p>
              </div>

              <SlackAuthButton />

              <div className="mt-8 border-t border-border pt-6">
                <p className="text-xs leading-relaxed text-muted-foreground">
                  By continuing, you agree to our
                </p>
                <p className="mt-1 text-xs leading-relaxed">
                  <a
                    href="/terms"
                    className="font-medium text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
                  >
                    Terms
                  </a>
                  <span className="text-muted-foreground"> and </span>
                  <a
                    href="/privacy"
                    className="font-medium text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
                  >
                    Privacy Policy
                  </a>
                </p>
              </div>
            </div>
          </div>
        </main>

        <Footer />
      </div>
    </>
  );
}

function Footer() {
  return (
    <footer className="relative px-6 py-6 md:px-10 md:py-8">
      <div className="flex flex-col items-start justify-between gap-3 text-xs text-muted-foreground md:flex-row md:items-center">
        <div className="flex items-center gap-2">
          <span aria-hidden="true" className="relative flex size-1.5">
            <span className="absolute inline-flex size-full animate-ping rounded-full bg-[#10B981] opacity-60" />
            <span className="relative inline-flex size-1.5 rounded-full bg-[#10B981]" />
          </span>
          <span>All systems operational</span>
        </div>
        <div className="flex items-center gap-5">
          <a
            href="https://github.com/firefightlabs/firefight"
            className="transition-colors hover:text-foreground"
            target="_blank"
            rel="noreferrer"
          >
            GitHub
          </a>
          <a href="/docs" className="transition-colors hover:text-foreground">
            Docs
          </a>
          <span className="tabular-nums">v1.0</span>
        </div>
      </div>
    </footer>
  );
}


