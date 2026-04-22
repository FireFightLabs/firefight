import { Head, useForm, usePage } from "@inertiajs/react";
import type { FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SlackAuthButton } from "@/modules/auth/components/slack-auth-button";
import type { SharedProps } from "@/types";

interface LoginPageProps extends SharedProps {
  [key: string]: unknown;
  inviteCodeClaimed: boolean;
}

export default function Login() {
  const { flash, inviteCodeClaimed } = usePage<LoginPageProps>().props;
  const form = useForm({ code: "" });

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    form.post("/invite-code/claim");
  };

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
                  Firefight is in public beta. New workspace access currently
                  requires an invite code before first sign-in.
                </p>
              </div>

              <div className="mb-6 rounded-lg border border-border/80 bg-muted/30 p-4 text-left">
                <p className="text-xs font-medium uppercase tracking-[0.18em] text-muted-foreground">
                  Public beta
                </p>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                  Existing members can sign in normally. Everyone else needs an
                  invite code before Slack can create or join a workspace.
                </p>
              </div>

              {flash.notice ? (
                <div className="mb-4 rounded-lg border border-emerald-500/20 bg-emerald-500/10 px-4 py-3 text-left text-sm text-emerald-800 dark:text-emerald-200">
                  {flash.notice}
                </div>
              ) : null}

              {flash.alert ? (
                <div className="mb-4 rounded-lg border border-destructive/20 bg-destructive/10 px-4 py-3 text-left text-sm text-destructive">
                  {flash.alert}
                </div>
              ) : null}

              <form className="mb-6 space-y-3 text-left" onSubmit={submit}>
                <div className="space-y-2">
                  <Label htmlFor="invite-code">Invite code</Label>
                  <Input
                    id="invite-code"
                    name="code"
                    value={form.data.code}
                    onChange={(event) => form.setData("code", event.target.value)}
                    placeholder="Enter your invite code"
                    autoCapitalize="characters"
                    autoCorrect="off"
                    spellCheck={false}
                  />
                </div>

                <Button type="submit" className="w-full" disabled={form.processing}>
                  {inviteCodeClaimed ? "Replace invite code" : "Claim invite code"}
                </Button>
              </form>

              {inviteCodeClaimed ? (
                <p className="mb-6 text-sm leading-relaxed text-foreground">
                  Invite code claimed. Continue with Slack when you're ready.
                </p>
              ) : null}

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
