---
description: Deep OWASP security sweep of the full app, all APIs, and internal services
---

Run a deep OWASP security sweep of the full app, all APIs, and any internal services.

Launch 3 Explore agents IN PARALLEL to cover different attack surfaces:

**Agent 1 — Controllers, auth, API security, CSRF, mass assignment**
- Authentication: how is it implemented, is every controller protected?
- Authorization: are resources scoped to the current user/workspace? Any IDOR risks?
- API auth mechanisms — are Slack webhook signatures verified?
- CSRF protection — `protect_from_forgery` config, API controller exemptions
- Strong params — any `permit!` or bare `update(params)` calls?
- Secrets — hardcoded credentials, env var vs credentials usage
- Check: `app/controllers/`, `app/models/`, `config/initializers/`, `config/application.rb`, `config/environments/`

**Agent 2 — Models, services, injection risks, data exposure**
- SQL injection: `where("#{...}")`, `order("#{...}")`, `find_by_sql`, raw `execute` calls
- Command injection: `system()`, `exec()`, backticks, `Open3`, `IO.popen`
- IDOR: `find(params[:id])` not scoped to current user/tenant — tenant isolation
- Sensitive data in logs, `as_json` over-exposure, PII in error messages
- Production config: `force_ssl`, `assume_ssl`, `config.hosts`, log level
- Token/secret generation — using `SecureRandom`? Any MD5/SHA1 for security purposes?
- Check: `app/models/`, `app/services/`, `app/workflows/`, `app/adapters/`, `config/`

**Agent 3 — Slack integration, dependencies, session security, headers**
- Slack signature verification: HMAC-SHA256, `secure_compare`, replay attack window
- Dependency vulnerabilities: `Gemfile`/`Gemfile.lock` — outdated or vulnerable gems
- Session security: timeout, cookie flags (Secure, HttpOnly, SameSite), fixation
- Security headers: CSP, HSTS, X-Frame-Options, X-Content-Type-Options
- File uploads, open redirects (`redirect_to params[:return_to]`), SSRF
- OAuth flows: state parameter validation, CSRF on callbacks
- Logging: `filter_parameters` config, PII in log output
- Check: `Gemfile`, `config/initializers/`, all API controllers

After all 3 agents complete, compile findings and report using AskUserQuestion with:
- Full findings listed in descending severity (CRITICAL → HIGH → MEDIUM → LOW)
- File path and line number for each finding
- Concrete fix for each finding
- Positives (what's already secure) listed at the end

Then ask the user which issues they want implemented, and whether any require product/architecture decisions before fixing (e.g. authorization models, RBAC).
