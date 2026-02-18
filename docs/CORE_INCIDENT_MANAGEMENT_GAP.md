# Core Incident Management Workflow Gap Analysis

## Purpose

This document captures the core incident management workflow gaps between Firefight and leading incident management products (incident.io, Rootly, FireHydrant).

Scope is intentionally limited to core incident management workflow. This excludes postmortems, on-call integrations, and AI features.

## Current Firefight Core (What Exists)

- Slack-first incident declaration via modal and slash commands
- Incident channel creation and metadata updates
- Severity and status updates through incident update modal
- Incident Lead assignment (single operational role)
- Quick actions message and incident announcement updates
- Action and follow-up tracking inside incident channels
- Incident update reminders based on next update time

## Core Workflow Gaps

### 1) Lifecycle Model Depth

Firefight has a basic live/closed model with `declared_at` and `resolved_at`, but lacks a full lifecycle state model used by mature incident programs.

Missing core lifecycle capabilities:

- First-class lifecycle stages: triage, started, acknowledged, mitigated, resolved, closed, cancelled
- Explicit timestamps per stage for high-quality operational analytics
- Strong distinction between "resolved" (technical fix complete) and "closed" (process complete)

### 2) Lifecycle Guardrails and Transition Rules

Lifecycle transitions are not constrained by policy.

Missing guardrails:

- Allowed transition graph (prevent invalid state jumps)
- Required fields by lifecycle stage (e.g. must provide certain data before resolving)
- Workspace-level lifecycle policy enforcement in Slack/UI/API

### 3) Responder Orchestration Beyond Incident Lead

Firefight currently operationalizes Incident Lead only.

Missing role orchestration:

- Multi-role response model (e.g. commander, comms lead, ops lead)
- Team-level assignment and responder mobilization workflows
- In-incident role handoff as a first-class workflow

### 4) Complete Core Command Surface

Some core commands are placeholders and not operational.

Missing implemented commands/workflows:

- Escalation
- Close/resolve finalization flow
- Timeline operator view/entry flow
- Active incident listing and quick navigation

### 5) Incident Relationship Management

No first-class relationship model exists for linked incidents.

Missing relationship workflows:

- Mark incident as duplicate (canonical + duplicate flow)
- Parent/sub-incident workflows for large multi-stream incidents
- Related incident linking for context continuity

### 6) Private Incident Access Lifecycle

`is_private` exists, but access lifecycle is limited.

Missing private incident controls:

- Incident-level access grant/revoke workflows
- Membership sync behavior with Slack channel participation
- Operator-grade private access management from incident context

### 7) Impacted Service/Component Workflow

No first-class impacted service/component model drives response routing.

Missing impact modeling:

- Mark impacted services/components during active incident
- Ownership-aware responder routing from impacted entities
- Use impacted entities in incident triage and coordination workflows

### 8) Timeline as an Operator-Grade Control Plane

Incident events are stored, but timeline operations are not yet first-class.

Missing timeline capabilities:

- Dedicated timeline workflows for adding and curating key events
- Clear system vs human event representation for responders
- Timeline ergonomics suitable for active command and review

### 9) Reopen and Retroactive Incident Workflows

Reopen semantics are implicit through status changes only.

Missing lifecycle operations:

- Explicit reopen workflow with clear operator behavior
- Retroactive incident creation and lifecycle reconstruction workflows

## Prioritized Delivery Plan (One at a Time)

## P0 Foundation

1. Lifecycle model expansion (states + timestamps)
2. Lifecycle transition rules and required-field guardrails
3. Multi-role/team assignment and handoff
4. Complete core command surface (escalate/close/timeline/list)
5. Incident relationships (duplicate + parent/sub + related)
6. Private incident access lifecycle management
7. Impacted service/component model and routing
8. Timeline operator workflows
9. Explicit reopen + retroactive workflows

## Execution Approach

- Deliver each gap as an isolated, testable increment
- Keep Slack workflow and UI behavior aligned per increment
- Prefer additive changes that preserve current production behavior
- Attach acceptance criteria and tests before starting implementation

## Tracking

Use this checklist to track implementation progress:

- [ ] 1. Lifecycle model expansion
- [ ] 2. Transition rules and guardrails
- [ ] 3. Multi-role/team orchestration
- [ ] 4. Core command completion
- [ ] 5. Incident relationships
- [ ] 6. Private incident access lifecycle
- [ ] 7. Impacted services/components
- [ ] 8. Timeline operator workflows
- [ ] 9. Reopen + retroactive workflows
