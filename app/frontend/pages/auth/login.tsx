import { Head, usePage } from "@inertiajs/react";

import { SlackAuthButton } from "@/modules/auth/components/slack-auth-button";
import type { SharedProps } from "@/types";

interface LoginPageProps extends SharedProps {
  [key: string]: unknown;
}

export default function Login() {
  const { flash } = usePage<LoginPageProps>().props;

  return (
    <div className="dark">
      <Head title="Sign in to Firefight" />
      <div className="relative flex min-h-svh flex-col bg-background text-foreground">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(115,211,238,0.03)_1px,transparent_1px),linear-gradient(to_bottom,rgba(115,211,238,0.03)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
        />

        <main className="relative flex flex-1 items-center justify-center px-6 py-12">
          <div className="w-full max-w-[420px]">
            <div className="relative rounded-[14px] border border-[rgba(115,211,238,0.3)] bg-card px-8 py-10 text-center shadow-[0_1px_2px_0_rgba(0,0,0,0.2),0_20px_60px_0_rgba(0,0,0,0.4),0_0px_60px_0_rgba(115,211,238,0.06)] sm:px-10 sm:py-12">
              <div className="mb-8 flex flex-col items-center space-y-4">
                <svg width="36" height="36" viewBox="20 20 34 39" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
                  <path d="M50.8096 30.2171C52.7322 32.9637 53.8622 36.3063 53.8623 39.9134L53.8564 40.3509C53.6246 49.4995 46.1351 56.8448 36.9307 56.845L36.4941 56.8392C35.8569 56.823 35.2282 56.7705 34.6104 56.6858L36.0596 54.3177C36.3476 54.3348 36.6383 54.345 36.9307 54.345C44.9005 54.3448 51.3623 47.8833 51.3623 39.9134C51.3622 37.2371 50.632 34.7317 49.3623 32.5833L50.8096 30.2171ZM36.9307 22.9827C38.8085 22.9828 40.6147 23.2894 42.3027 23.8538L40.7695 26.0003C39.5471 25.6637 38.26 25.4827 36.9307 25.4827C28.961 25.4829 22.5003 31.9437 22.5 39.9134C22.5 42.9326 23.4275 45.735 25.0127 48.052L23.4805 50.1966C21.2976 47.3457 20 43.7813 20 39.9134C20.0003 30.563 27.5803 22.9829 36.9307 22.9827Z" fill="#73D3EE"/>
                  <path d="M23.336 59L51.2016 20L27.6572 58.4694L23.336 59Z" fill="#73D3EE"/>
                </svg>
                <div className="space-y-2">
                  <h1 className="text-[1.75rem] font-medium leading-[1.15] tracking-[-0.02em] text-foreground">
                    Sign in
                  </h1>
                  <p className="mx-auto max-w-[32ch] text-[0.9375rem] leading-relaxed text-muted-foreground">
                    Connect your Slack workspace to get started. We&apos;ll walk
                    you through setup on first sign-in.
                  </p>
                </div>
              </div>

              {flash.notice ? (
                <div className="mb-4 rounded-lg border border-emerald-500/20 bg-emerald-500/10 px-4 py-3 text-left text-sm text-emerald-300">
                  {flash.notice}
                </div>
              ) : null}

              {flash.alert ? (
                <div className="mb-4 rounded-lg border border-destructive/20 bg-destructive/10 px-4 py-3 text-left text-sm text-destructive">
                  {flash.alert}
                </div>
              ) : null}

              <SlackAuthButton />

              <div className="mt-8 border-t pt-6" style={{ borderColor: "rgba(115,211,238,0.25)" }}>
                <p className="text-xs leading-relaxed text-muted-foreground">
                  By continuing, you agree to our
                </p>
                <p className="mt-1 text-xs leading-relaxed">
                  <a
                    href="/terms"
                    className="font-semibold text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
                  >
                    Terms
                  </a>
                  <span className="text-muted-foreground"> and </span>
                  <a
                    href="/privacy"
                    className="font-semibold text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
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
    </div>
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
