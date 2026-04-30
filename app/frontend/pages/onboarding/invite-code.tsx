import { Head, useForm, usePage } from "@inertiajs/react";
import type { FormEvent } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { SharedProps } from "@/types";

interface InviteCodePageProps extends SharedProps {
  [key: string]: unknown;
  teamName: string;
}

export default function InviteCode() {
  const { flash, teamName } = usePage<InviteCodePageProps>().props;
  const form = useForm({ code: "" });

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    form.post("/invite-code/claim");
  };

  return (
    <>
      <Head title="Enter invite code" />
      <div className="relative flex min-h-svh flex-col bg-background text-foreground">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[linear-gradient(to_right,rgba(10,30,46,0.035)_1px,transparent_1px),linear-gradient(to_bottom,rgba(10,30,46,0.035)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
        />

        <main className="relative flex flex-1 items-center justify-center px-6 py-12">
          <div className="w-full max-w-[420px]">
            <div className="relative rounded-xl border border-border bg-card px-8 py-10 shadow-[0_1px_0_0_rgba(10,30,46,0.02),0_1px_2px_0_rgba(10,30,46,0.04),0_8px_24px_-8px_rgba(10,30,46,0.08)] sm:px-10 sm:py-12">
              <div className="mb-8 space-y-2 text-center">
                <p className="text-xs font-medium uppercase tracking-[0.18em] text-muted-foreground">
                  Public beta
                </p>
                <h1 className="text-[1.75rem] font-medium leading-[1.15] tracking-[-0.02em] text-foreground">
                  Enter invite code
                </h1>
                <p className="mx-auto max-w-[34ch] text-[0.9375rem] leading-relaxed text-muted-foreground">
                  Firefight is in public beta. Installing to{" "}
                  <span className="font-medium text-foreground">{teamName}</span>{" "}
                  requires a one-time invite code.
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

              <form className="space-y-3 text-left" onSubmit={submit}>
                <div className="space-y-2">
                  <Label htmlFor="invite-code">Invite code</Label>
                  <Input
                    id="invite-code"
                    name="code"
                    value={form.data.code}
                    onChange={(event) =>
                      form.setData("code", event.target.value)
                    }
                    placeholder="Enter your invite code"
                    autoCapitalize="characters"
                    autoCorrect="off"
                    spellCheck={false}
                  />
                </div>

                <Button
                  type="submit"
                  className="w-full"
                  disabled={form.processing}
                >
                  Continue
                </Button>
              </form>

              <p className="mt-6 text-center text-xs leading-relaxed text-muted-foreground">
                Don&apos;t have a code?{" "}
                <a
                  href="mailto:hello@firefight.app"
                  className="font-medium text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
                >
                  Request access
                </a>
                .
              </p>
            </div>
          </div>
        </main>
      </div>
    </>
  );
}
