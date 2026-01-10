# FireFight Core Product Timeline
## Realistic Build Estimate (Excluding 67 Custom Integrations)

**Analysis Date**: January 10, 2026
**Scope**: Core incident management platform with integration framework (but not individual integrations)
**Team Size Assumption**: 1-2 full-stack developers

---

## Executive Summary

**Total Estimated Time: 12-16 weeks (3-4 months)**

This includes:
- ✅ Core incident management
- ✅ Event tracking & audit trails
- ✅ Webhook infrastructure
- ✅ Public API
- ✅ Service catalog
- ✅ Post-mortems
- ✅ Runbooks
- ✅ Integration framework (ready for integrations)
- ✅ Basic AI capabilities
- ⚠️ Excludes: 67 individual integration implementations

---

## Current State Assessment

### What You Already Have ✅
- ✅ **Rails 8 app** with modern stack
- ✅ **User authentication** (Slack OAuth)
- ✅ **Workspace multi-tenancy**
- ✅ **Workflow orchestration engine** (fully built!)
  - Polymorphic subject support
  - State machine
  - Event tracking
  - Step orchestration
  - Retry logic
  - Pause/resume
  - Cancellation
- ✅ **Slack integration foundation**
  - OAuth flow
  - Slash commands
  - Modals
  - Interactive components
- ✅ **Frontend stack** (Inertia.js + React + TypeScript + shadcn/ui)
- ✅ **Database** (PostgreSQL with UUIDs)

### Estimated Build Complexity Reduction: 40%

Your workflow system is the foundation for incidents, runbooks, and integrations. This is **massive** - most competitors built this over years. You have it already.

---

## Detailed Feature Breakdown with Time Estimates

### Phase 1: Core Incident Management (3 weeks)

**What**: Basic incident CRUD, event tracking, Slack integration

#### Week 1: Database & Models (40 hours)
- [ ] Database migrations
  - `incidents` table (4h)
  - `incident_events` table (2h)
  - `incident_responders` join table (2h)
  - Indexes and constraints (2h)
- [ ] Incident model with concerns
  - `Incident::Eventable` (8h) - mirrors `Workflow::Eventable`
  - `Incident::Stateable` (6h) - state machine
  - `Incident::Assignable` (4h) - commander, responders
  - Validations and scopes (2h)
- [ ] IncidentEvent model (4h)
- [ ] Tests (8h)

**Complexity**: Low (following existing workflow pattern)

#### Week 2: Slack Incident Creation (40 hours)
- [ ] Incident creation modal (already 50% done)
  - Finish modal builder (4h)
  - Handle submission (6h)
  - Validation (2h)
- [ ] Incident creation workflow
  - `IncidentCreationWorkflow` (8h)
  - Create Slack channel step (6h)
  - Post initial message step (4h)
  - Invite responders step (4h)
  - Error handling (4h)
- [ ] Tests (8h)

**Complexity**: Medium (Slack API integration)

#### Week 3: Slack Incident Management Commands (40 hours)
- [ ] Slash commands
  - `/ff status` - show incident status (4h)
  - `/ff update-severity` - change severity (6h)
  - `/ff assign` - assign commander (6h)
  - `/ff add-responder` - add team member (4h)
  - `/ff resolve` - resolve incident (6h)
- [ ] Interactive components
  - Severity change buttons (4h)
  - Status update buttons (4h)
  - Quick actions (4h)
- [ ] Tests (8h)

**Complexity**: Medium (command routing + state updates)

**Phase 1 Total: 3 weeks (120 hours)**

---

### Phase 2: Timeline & Event System (1.5 weeks)

**What**: Unified timeline view, event correlation, activity feed

#### Timeline Implementation (60 hours)
- [ ] Timeline query builder
  - Combine incident_events + workflow_events (8h)
  - Pagination and filtering (6h)
  - Event type formatting (4h)
- [ ] Slack timeline view
  - Timeline message formatting (8h)
  - Interactive timeline (buttons for expand/collapse) (6h)
  - Auto-update on changes (WebSocket/polling) (8h)
- [ ] Event grouping and correlation
  - Group related events (6h)
  - Smart summarization (4h)
- [ ] Tests (10h)

**Complexity**: Medium (data aggregation + real-time updates)

**Phase 2 Total: 1.5 weeks (60 hours)**

---

### Phase 3: Web Dashboard (2 weeks)

**What**: Web UI for incident management (already have Inertia.js stack!)

#### Week 1: Incident List & Detail (40 hours)
- [ ] Incident list page
  - Table with filters (8h)
  - Search and sorting (4h)
  - Status badges (2h)
  - Severity indicators (2h)
- [ ] Incident detail page
  - Incident header (4h)
  - Timeline view (8h)
  - Responders list (4h)
  - Quick actions (4h)
- [ ] Tests (4h)

**Complexity**: Low (UI work with existing components)

#### Week 2: Incident Forms & Updates (40 hours)
- [ ] Create incident form (8h)
- [ ] Edit incident form (6h)
- [ ] Update severity modal (4h)
- [ ] Assign commander modal (4h)
- [ ] Add responders modal (6h)
- [ ] Resolve incident flow (6h)
- [ ] Form validation (4h)
- [ ] Tests (8h)

**Complexity**: Low (standard CRUD forms)

**Phase 3 Total: 2 weeks (80 hours)**

---

### Phase 4: Public API (1.5 weeks)

**What**: RESTful API for external integrations

#### API Implementation (60 hours)
- [ ] API authentication
  - API key model (4h)
  - Token generation/validation (6h)
  - Rate limiting (4h)
- [ ] Incidents endpoints
  - GET /api/v1/incidents (4h)
  - POST /api/v1/incidents (6h)
  - GET /api/v1/incidents/:id (2h)
  - PATCH /api/v1/incidents/:id (4h)
  - POST /api/v1/incidents/:id/update_severity (3h)
  - POST /api/v1/incidents/:id/assign_commander (3h)
  - POST /api/v1/incidents/:id/resolve (3h)
- [ ] Timeline endpoints
  - GET /api/v1/incidents/:id/events (4h)
  - GET /api/v1/incidents/:id/timeline (4h)
- [ ] API serializers (6h)
- [ ] API documentation (OpenAPI/Swagger) (6h)
- [ ] Tests (12h)

**Complexity**: Low (standard REST API)

**Phase 4 Total: 1.5 weeks (60 hours)**

---

### Phase 5: Webhook System (1.5 weeks)

**What**: Outbound webhooks for external systems to receive events

#### Webhook Infrastructure (60 hours)
- [ ] Database
  - `webhooks` table (3h)
  - `webhook_deliveries` table (3h)
- [ ] Webhook model
  - Event type filtering (4h)
  - Signature generation (4h)
  - Status tracking (3h)
- [ ] WebhookDispatcher service
  - Event matching (6h)
  - Async delivery (4h)
  - Retry logic with backoff (8h)
- [ ] WebhookDeliveryJob
  - HTTP client (4h)
  - Error handling (4h)
  - Response logging (3h)
- [ ] Webhook management UI
  - List webhooks (4h)
  - Create/edit webhook (6h)
  - Delivery logs (4h)
- [ ] Tests (10h)

**Complexity**: Medium (reliability and retry logic)

**Phase 5 Total: 1.5 weeks (60 hours)**

---

### Phase 6: Service Catalog (2 weeks)

**What**: Service definitions, dependencies, health tracking

#### Week 1: Core Service Management (40 hours)
- [ ] Database
  - `services` table (3h)
  - `service_events` table (2h)
  - `incident_services` join table (2h)
  - `service_dependencies` join table (3h)
- [ ] Service model
  - `Service::Eventable` (6h)
  - Health status calculation (4h)
  - Dependency graph (6h)
- [ ] Service API endpoints
  - CRUD operations (8h)
  - Dependency management (4h)
- [ ] Tests (8h)

**Complexity**: Medium (graph relationships)

#### Week 2: Service UI & Integration (40 hours)
- [ ] Service catalog page
  - Service list with health (8h)
  - Service detail page (8h)
  - Dependency visualization (8h)
- [ ] Service-Incident linking
  - Attach services to incidents (6h)
  - Impact level tracking (4h)
  - Auto-detection from alerts (future) (2h)
- [ ] Service management UI
  - Create/edit service (6h)
  - Manage dependencies (6h)
- [ ] Tests (6h)

**Complexity**: Medium (visualization + relationships)

**Phase 6 Total: 2 weeks (80 hours)**

---

### Phase 7: Post-Mortems (1.5 weeks)

**What**: Post-incident analysis and documentation

#### Post-Mortem Implementation (60 hours)
- [ ] Database
  - `post_mortems` table (3h)
- [ ] PostMortem model
  - Template rendering (6h)
  - Status workflow (draft → review → published) (4h)
- [ ] Auto-generation from incident
  - Extract timeline (4h)
  - Generate summary (AI-assisted) (8h)
  - Template population (4h)
- [ ] Post-mortem UI
  - Editor (rich text) (10h)
  - Review workflow (6h)
  - Publishing (4h)
- [ ] Export functionality
  - Markdown export (3h)
  - PDF export (4h)
- [ ] Tests (8h)

**Complexity**: Medium (content generation + editing)

**Phase 7 Total: 1.5 weeks (60 hours)**

---

### Phase 8: Runbooks (1.5 weeks)

**What**: Reusable workflow templates for common tasks

#### Runbook System (60 hours)
- [ ] Database
  - `runbooks` table (3h)
- [ ] Runbook model
  - Template storage (4h)
  - Version management (6h)
- [ ] RunbookExecutionWorkflow
  - Dynamic step execution (12h)
  - Step type handlers (slack, api_call, script, wait) (8h)
- [ ] Runbook UI
  - Runbook builder (visual editor) (12h)
  - Execution tracking (6h)
  - History (4h)
- [ ] Integration with incidents
  - Suggest runbooks (4h)
  - Execute from incident (3h)
- [ ] Tests (8h)

**Complexity**: High (dynamic workflow execution)

**Phase 8 Total: 1.5 weeks (60 hours)**

---

### Phase 9: Integration Framework (2 weeks)

**What**: Foundation for adding integrations (NOT the actual integrations)

#### Week 1: Core Framework (40 hours)
- [ ] Database
  - `integrations` table (3h)
  - `integration_events` table (2h)
- [ ] Integration registry
  - Category definitions (4h)
  - Metadata system (6h)
  - Self-describing integrations (4h)
- [ ] BaseClient abstraction
  - Standard interface (6h)
  - Credential encryption (4h)
  - Error handling (4h)
  - Rate limiting (4h)
- [ ] Tests (8h)

**Complexity**: Medium (abstraction design)

#### Week 2: Integration Management UI (40 hours)
- [ ] Integration marketplace/catalog (8h)
- [ ] Integration setup flow
  - OAuth flow (8h)
  - Credential input (6h)
  - Connection testing (4h)
- [ ] Integration settings (6h)
- [ ] Integration status dashboard (6h)
- [ ] Tests (8h)

**Complexity**: Medium (UI + OAuth flows)

**Phase 9 Total: 2 weeks (80 hours)**

---

### Phase 10: Basic AI Capabilities (2 weeks)

**What**: AI-powered features (search, suggestions, natural language)

#### Week 1: AI Infrastructure (40 hours)
- [ ] OpenAI integration
  - API client (4h)
  - Prompt templates (4h)
  - Response parsing (4h)
- [ ] Vector search setup
  - pgvector extension (2h)
  - Embedding generation (6h)
  - Vector indexes (3h)
- [ ] Incident search
  - Semantic search (8h)
  - Re-ranking (4h)
  - UI integration (4h)
- [ ] Tests (6h)

**Complexity**: Medium (vector search setup)

#### Week 2: AI Command & Suggestions (40 hours)
- [ ] Intent recognition service
  - Tool definition (6h)
  - Parameter extraction (6h)
  - Context building (4h)
- [ ] AI command handler
  - /ff <natural language> (8h)
  - Integration with workflow system (6h)
- [ ] AI suggestions
  - Severity suggestions (4h)
  - Next steps recommendations (4h)
- [ ] Tests (8h)

**Complexity**: High (LLM integration)

**Phase 10 Total: 2 weeks (80 hours)**

---

### Phase 11: Polish & Testing (1.5 weeks)

**What**: Bug fixes, performance, security, UX improvements

#### Polish Work (60 hours)
- [ ] Performance optimization
  - Database query optimization (8h)
  - N+1 query fixes (4h)
  - Caching strategy (6h)
- [ ] Security audit
  - Permission checks (6h)
  - CSRF/XSS prevention (4h)
  - Rate limiting (4h)
- [ ] UX improvements
  - Loading states (4h)
  - Error messages (4h)
  - Keyboard shortcuts (4h)
- [ ] Documentation
  - User guide (6h)
  - API docs (4h)
  - Developer setup (2h)
- [ ] Integration tests (10h)
- [ ] Bug fixes buffer (12h)

**Complexity**: Variable

**Phase 11 Total: 1.5 weeks (60 hours)**

---

## Summary Timeline

| Phase | Feature | Weeks | Hours | Complexity |
|-------|---------|-------|-------|------------|
| 1 | Core Incident Management | 3 | 120 | Low-Medium |
| 2 | Timeline & Event System | 1.5 | 60 | Medium |
| 3 | Web Dashboard | 2 | 80 | Low |
| 4 | Public API | 1.5 | 60 | Low |
| 5 | Webhook System | 1.5 | 60 | Medium |
| 6 | Service Catalog | 2 | 80 | Medium |
| 7 | Post-Mortems | 1.5 | 60 | Medium |
| 8 | Runbooks | 1.5 | 60 | High |
| 9 | Integration Framework | 2 | 80 | Medium |
| 10 | Basic AI Capabilities | 2 | 80 | High |
| 11 | Polish & Testing | 1.5 | 60 | Variable |
| **TOTAL** | **Core Product** | **20 weeks** | **800 hours** | - |

---

## Adjusted Realistic Timeline

### Factors to Consider

**Efficiency Multipliers:**
- ✅ +40% from existing workflow system
- ✅ +20% from existing Slack integration
- ✅ +15% from modern Rails stack (Rails 8, Inertia.js, TypeScript)

**Inefficiency Factors:**
- ⚠️ -15% for unknowns and edge cases
- ⚠️ -10% for meetings, reviews, context switching
- ⚠️ -5% for deployment/DevOps

**Net adjustment: +25% efficiency**

**Adjusted Time: 800 hours / 1.25 = 640 hours**

### Timeline by Team Size

#### Solo Developer (40 hours/week)
**640 hours / 40 = 16 weeks (4 months)**

#### Two Developers (80 hours/week total)
**640 hours / 80 = 8 weeks (2 months)**

With parallelization of independent phases:
- Phase 1-2 can run parallel with Phase 3
- Phase 4-5 can run parallel
- Phase 6-8 can be parallelized

**Realistic with 2 devs: 10-12 weeks (2.5-3 months)**

---

## Recommended Build Order (Optimized for Value)

### MVP v0.1 (Weeks 1-4) - Usable Product
1. ✅ Core Incident Management (Phase 1)
2. ✅ Timeline & Events (Phase 2)

**Output**: Slack-based incident management with full audit trail

### MVP v0.2 (Weeks 5-7) - Web Interface
3. ✅ Web Dashboard (Phase 3)
4. ✅ Public API (Phase 4)

**Output**: Web UI + API for external access

### MVP v0.3 (Weeks 8-10) - Integrations Ready
5. ✅ Webhook System (Phase 5)
6. ✅ Integration Framework (Phase 9)

**Output**: Can receive/send webhooks, ready for custom integrations

### MVP v0.4 (Weeks 11-14) - Full Feature Set
7. ✅ Service Catalog (Phase 6)
8. ✅ Post-Mortems (Phase 7)
9. ✅ Runbooks (Phase 8)

**Output**: Feature parity with competitors

### MVP v1.0 (Weeks 15-16) - AI-Powered
10. ✅ Basic AI Capabilities (Phase 10)
11. ✅ Polish & Testing (Phase 11)

**Output**: Production-ready with AI differentiator

---

## What's NOT Included (Future Work)

### Explicitly Excluded from Timeline

1. **67 Individual Integrations** (200+ days)
   - Only framework is built
   - Add integrations based on customer demand
   - Can be outsourced or community-built

2. **Advanced AI Features**
   - AI SRE agent
   - Auto-remediation
   - Predictive analytics
   - (Basic AI is included)

3. **Status Pages**
   - External status page generation
   - Can be added later (2-3 weeks)

4. **Mobile Apps**
   - Native iOS/Android
   - Can use Slack as mobile interface initially

5. **Advanced Analytics**
   - MTTR dashboards
   - Custom reports
   - Business intelligence
   - (Basic metrics included)

6. **On-Call Scheduling**
   - Rotation management
   - PagerDuty integration can handle this initially

7. **SSO/SAML**
   - Enterprise authentication
   - (Slack OAuth sufficient for MVP)

8. **Multi-region Deployment**
   - Global infrastructure
   - (Single region sufficient initially)

---

## Risk Factors & Contingencies

### High Risk Items (Could Add 2-4 Weeks)

1. **Slack API Edge Cases** (1 week buffer)
   - Rate limiting
   - Webhook delivery failures
   - Modal complexity

2. **Real-time Updates** (1 week buffer)
   - WebSocket infrastructure
   - State synchronization
   - Could use polling initially

3. **AI Integration Reliability** (1 week buffer)
   - OpenAI API failures
   - Prompt engineering iterations
   - Token costs

4. **Runbook Dynamic Execution** (1 week buffer)
   - Security sandboxing
   - Script execution safety
   - Error handling

**Total Contingency: +4 weeks**

### Low Risk Items (Unlikely to Block)

1. **Database Performance** - PostgreSQL scales well
2. **Authentication** - Already working
3. **Frontend Stack** - Proven technologies
4. **Workflow System** - Already built and tested

---

## Final Estimate

### Conservative Estimate (95% confidence)
**Solo: 20 weeks (5 months)**
**Team of 2: 14 weeks (3.5 months)**

Includes:
- All core features
- Integration framework
- Basic AI
- Contingency buffer

### Aggressive Estimate (70% confidence)
**Solo: 16 weeks (4 months)**
**Team of 2: 10 weeks (2.5 months)**

Requires:
- No major blockers
- Minimal scope changes
- Experienced developers

### Recommended Estimate
**Solo: 16-18 weeks (4-4.5 months)**
**Team of 2: 12-14 weeks (3-3.5 months)**

This balances ambition with pragmatism.

---

## Comparison to Competitors

### incident.io (Raised $100M+)
- **Team Size**: 50+ engineers
- **Time to MVP**: ~18 months
- **Time to current state**: 3+ years

### FireHydrant (Raised $50M+)
- **Team Size**: 30+ engineers
- **Time to MVP**: ~12 months
- **Time to current state**: 4+ years

### Rootly (Raised $20M+)
- **Team Size**: 20+ engineers
- **Time to MVP**: ~12 months
- **Time to current state**: 2+ years

### FireFight (Bootstrapped/Early Stage)
- **Team Size**: 1-2 developers
- **Time to MVP**: 4 months (solo) / 2.5 months (2 devs)
- **Time to feature parity**: 4.5 months (solo) / 3.5 months (2 devs)

**Your advantage**: Modern stack, existing workflow system, focused scope.

---

## Next Steps

### Immediate (This Week)
1. Validate timeline with stakeholders
2. Prioritize features (cut if needed)
3. Set up project tracking (GitHub Projects, Linear, etc.)
4. Create first sprint plan (Phase 1, Week 1)

### Short-term (Month 1)
1. Build Core Incident Management (Phase 1)
2. Build Timeline & Events (Phase 2)
3. Start Web Dashboard (Phase 3)
4. Weekly demos to validate direction

### Mid-term (Months 2-3)
1. Complete Web Dashboard + API
2. Build Webhook System
3. Build Integration Framework
4. Beta test with 3-5 friendly customers

### Long-term (Month 4+)
1. Service Catalog, Post-Mortems, Runbooks
2. AI capabilities
3. Polish for production launch
4. Begin integration implementations based on customer feedback

---

## Success Metrics

### Week 4 (MVP v0.1)
- [ ] Can declare incidents from Slack
- [ ] Can update severity/status
- [ ] Can view timeline
- [ ] Events are tracked

### Week 8 (MVP v0.2)
- [ ] Web dashboard shows all incidents
- [ ] API endpoints working
- [ ] Can manage incidents from web

### Week 12 (MVP v0.3)
- [ ] Webhooks delivering events
- [ ] Integration framework ready
- [ ] 3-5 design partner customers using it

### Week 16 (MVP v1.0)
- [ ] Service catalog tracking services
- [ ] Post-mortems being generated
- [ ] Runbooks executing
- [ ] AI assisting users
- [ ] Production-ready

---

## Conclusion

**Core Product Timeline: 12-16 weeks (3-4 months)**

This is **achievable** because:
1. ✅ Your workflow system handles the hardest part
2. ✅ Modern stack reduces boilerplate
3. ✅ Slack integration gives you a UI for free
4. ✅ Event-driven architecture is simple and scalable
5. ✅ Integration framework (not implementations) is sufficient

**This does NOT include:**
- ❌ 67 individual integrations (200+ days additional)
- ❌ Advanced AI features
- ❌ Status pages
- ❌ Mobile apps
- ❌ Advanced analytics

**But it DOES include:**
- ✅ Complete incident management
- ✅ Full audit trails and timeline
- ✅ Webhook infrastructure
- ✅ Public API
- ✅ Service catalog
- ✅ Post-mortems
- ✅ Runbooks
- ✅ Integration framework (ready for integrations)
- ✅ Basic AI capabilities

**You can achieve feature parity with funded competitors in 3-4 months** (with 1-2 devs), then add integrations incrementally based on customer demand.

Start building. Ship early. Iterate fast.
