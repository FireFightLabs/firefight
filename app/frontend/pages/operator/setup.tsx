import { AuthLayout } from "@/components/auth/auth-layout";
import { CardHeader } from "@/components/auth/card-header";
import { operatorSetupPath } from "@/lib/routes";
import { CodeForm } from "@/pages/operator/components/code-form";
import { QrCode } from "@/pages/operator/components/qr-code";

interface SetupProps {
  qr: boolean[][];
  secret: string;
  account: string;
}

export default function OperatorSetup({ qr, secret, account }: SetupProps) {
  return (
    <AuthLayout title="Set up your authenticator" variant="centered">
      <CardHeader
        overline="Operator console"
        title="Set up your authenticator"
        subtitle="The console asks for a code from an authenticator app each time you open it. Any app works, such as 1Password, Google Authenticator or Authy."
      />
      <div className="flex flex-col gap-8">
        <div className="flex flex-col items-center gap-4">
          <QrCode modules={qr} label={`QR code for the Firefight Operator account ${account}`} />
          <div className="text-center">
            <p className="text-muted-foreground text-xs">Or enter this key by hand</p>
            <p className="mt-1 font-mono text-sm tracking-wider select-all">{secret}</p>
          </div>
        </div>
        <CodeForm
          action={operatorSetupPath()}
          label="Code from the app"
          submitLabel="Confirm and continue"
          hint="Scan the code, then enter the six digits the app shows."
          digitsOnly
        />
      </div>
    </AuthLayout>
  );
}
