# Operator console

`/operator` is for the people who run a Firefight install, not for a workspace. It holds the jobs dashboard today, and the workflows, incident process and Halon screens as they land.

## Who gets in

- **An operator is a user id in `OPERATOR_USER_IDS`**, comma separated, read on every request (`OperatorCredential.operator?`). It is deploy config, so nothing a workspace can edit makes someone an operator. A user id rather than an email, since an email is only as good as whichever sign-in method last vouched for it.
- **Anyone else gets the app's own not found page**, signed in or not, on every console address including the jobs dashboard (`Operator::BaseController#require_operator!`). The console does not reveal it exists. Flightdeck serves its own stylesheet, script and fonts without a check, by design, so an asset address can show that it is mounted, and nothing more.
- **Then an authenticator code**, asked for again every `OperatorCredential::VERIFIED_FOR` (12 hours) in a session, so a taken-over sign-in alone opens nothing. Any TOTP app works.

## The second factor

`OperatorCredential`, one row per operator:

- **Setup** at `/operator/setup` shows a QR code (drawn by the page from the squares `rqrcode` returns, so no markup crosses to the browser) and the key in groups of four. The secret is created once and kept until the first code confirms it, so a mistyped code does not mean scanning again. It is encrypted.
- **Recovery codes**: ten, each working once, handed back once when setup is confirmed and rendered rather than redirected with, so they sit in no address, flash or log. Only an HMAC of each is stored.
- **A code works once.** The step it belongs to is claimed with one guarded `update_all`, so the same code cannot open two sessions, even from two requests at once. A code from the step before is taken, for clock drift.
- **Five wrong answers lock the factor for 15 minutes**, counted on the row so the lock holds across every process. A lock that has run out starts the count again. Rails' `rate_limit` is not used, since its count lives in the cache, which is off in tests and can be split per process.
- **After a correct code** the browser loads the next screen whole (`inertia_location`), since Flightdeck is not an Inertia page.
- **A lost phone and lost recovery codes**: `bin/rails 'operator:reset_authenticator[USER_ID]'` removes the row, and the next visit sets up anew.

## Jobs

Flightdeck (`solid_queue-flightdeck`) is mounted at `/operator/jobs`, with `Operator::FlightdeckController` as its base controller, so every one of its pages runs both checks above. It reads Solid Queue's own tables. The test database has none, so tests prove the checks and not Flightdeck's pages.
