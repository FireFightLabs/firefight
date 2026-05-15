import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  PERMISSION_GROUPS,
  TOTAL_SCOPES,
} from "@/modules/auth/lib/scope-permissions";

export function PermissionsDialog() {
  return (
    <Dialog>
      <DialogTrigger asChild>
        <button
          type="button"
          className="mt-5 inline-flex w-full cursor-pointer items-center justify-center gap-1.5 rounded text-xs text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-card"
        >
          See all {TOTAL_SCOPES} permissions
          <span aria-hidden="true" className="translate-y-[-0.5px]">
            →
          </span>
        </button>
      </DialogTrigger>

      <DialogContent
        style={{
          maxWidth: "560px",
          maxHeight: "min(85vh, 720px)",
          display: "grid",
          gridTemplateRows: "auto minmax(0, 1fr)",
        }}
        className="w-[calc(100vw-2rem)] gap-0 overflow-hidden border-border/70 bg-card p-0 shadow-[0_24px_60px_-24px_rgba(10,30,46,0.22),0_8px_20px_-8px_rgba(10,30,46,0.08)] [&>button]:text-muted-foreground [&>button]:hover:text-foreground"
      >
        <DialogHeader className="space-y-1.5 border-b border-border/60 px-6 pt-6 pb-5 sm:text-left">
          <DialogTitle>Permissions Firefight needs</DialogTitle>
          <DialogDescription className="text-base font-medium leading-relaxed text-foreground">
            Slack groups these OAuth scopes by what they let Firefight do in
            your workspace.
          </DialogDescription>
        </DialogHeader>

        <div className="overflow-y-auto overscroll-contain">
          <div className="px-6 pt-7 pb-7">
            {PERMISSION_GROUPS.map((group) => (
              <section
                key={group.title}
                className="border-t border-border/50 pt-8 first:border-t-0 first:pt-0"
              >
                <div className="mb-5">
                  <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground/65 tabular-nums">
                    {group.scopes.length} scope
                    {group.scopes.length === 1 ? "" : "s"}
                  </p>
                  <h3 className="mt-2 text-sm font-semibold text-foreground">
                    {group.title}
                  </h3>
                  <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                    {group.description}
                  </p>
                </div>

                <dl className="space-y-5 pb-2">
                  {group.scopes.map((scope) => (
                    <div key={scope.name} className="space-y-[7px]">
                      <dt>
                        <code className="inline-block rounded-[4px] bg-foreground/[0.05] px-[7px] py-[3px] font-mono text-xs font-semibold leading-none text-foreground">
                          {scope.name}
                        </code>
                      </dt>
                      <dd className="text-sm leading-relaxed text-foreground/85">
                        {scope.explanation}
                        {scope.boundary ? (
                          <>
                            {" "}
                            <span className="italic text-foreground/55">
                              {scope.boundary}
                            </span>
                          </>
                        ) : null}
                      </dd>
                    </div>
                  ))}
                </dl>
              </section>
            ))}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
