import { useForm, usePage } from "@inertiajs/react";
import type { FormEvent } from "react";

import { Card } from "@/components/card";
import { FireFightLogo } from "@/components/fire-fight-logo";
import { FlashAlerts } from "@/components/flash-alerts";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { claimInviteCodePath } from "@/lib/routes";
import { AuthLayout } from "@/modules/auth/components/auth-layout";
import type { SharedProps } from "@/types";

interface InviteCodePageProps extends SharedProps {
  [key: string]: unknown;
  teamName: string;
}

export default function InviteCode() {
  const { teamName } = usePage<InviteCodePageProps>().props;
  const form = useForm({ code: "" });

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    form.post(claimInviteCodePath());
  };

  return (
    <AuthLayout title="Enter invite code" containerClassName="max-w-[420px]">
      <Card variant="glow">
        <div className="mb-8 flex flex-col items-center space-y-4 text-center">
          <FireFightLogo />
          <div className="space-y-2">
            <p className="text-xs font-medium uppercase tracking-[0.18em] text-muted-foreground">
              Public beta
            </p>
            <h1 className="text-2xl font-semibold tracking-tight text-foreground">
              Enter invite code
            </h1>
            <p className="mx-auto max-w-[34ch] text-sm leading-relaxed text-muted-foreground">
              Firefight is in public beta. Installing to{" "}
              <span className="whitespace-nowrap font-medium text-foreground">{teamName}</span>{" "}
              requires a one-time invite code.
            </p>
          </div>
        </div>

        <FlashAlerts className="mb-4" />

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
              className="border-primary/50 focus-visible:ring-1"
              style={{ backgroundColor: "#071826" }}
            />
          </div>

          <Button
            type="submit"
            className="w-full cursor-pointer transition-shadow hover:shadow-[0_0_12px_rgba(115,211,238,0.2)]"
            disabled={form.processing}
          >
            Continue
          </Button>
        </form>

        <div className="mt-6 border-t border-primary/25 pt-4">
          <p className="text-center text-xs leading-relaxed text-muted-foreground">
            Don&apos;t have a code?{" "}
            <a
              href="mailto:hello@firefight.app"
              className="font-semibold text-foreground underline decoration-border underline-offset-[3px] transition-colors hover:decoration-foreground"
            >
              Request access
            </a>
            .
          </p>
        </div>
      </Card>
    </AuthLayout>
  );
}
