import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import { Button } from "@/components/ui/button";
import { operatorRootPath } from "@/lib/routes";

// Shown once, straight after setup. They are kept only in a form that cannot be read back.
export default function OperatorRecoveryCodes({ codes }: { codes: string[] }) {
  return (
    <AuthLayout title="Save your recovery codes" variant="centered">
      <CardHeader
        overline="Operator console"
        title="Save your recovery codes"
        subtitle="If you lose your phone, each of these opens the console once. This is the only time they are shown, so keep them in your password manager."
      />
      <div className="flex flex-col gap-6">
        <ol className="grid grid-cols-2 gap-2 rounded-lg border border-border bg-muted/40 p-4">
          {codes.map((code) => (
            <li key={code} className="text-center font-mono text-sm tracking-wider select-all">
              {code}
            </li>
          ))}
        </ol>
        {/* A full page load, since the console's first screen, Flightdeck, is not an Inertia page. */}
        <Button asChild size="lg">
          <a href={operatorRootPath()}>I saved them, open the console</a>
        </Button>
      </div>
    </AuthLayout>
  );
}
