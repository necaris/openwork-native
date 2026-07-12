---
title: "feat: session workflow improvements"
type: plan
date: 2026-07-11
status: complete
confidence: high
---

# Session Workflow Improvements

Improve the resume-first workflow by giving new sessions useful titles, making session selection discoverable, and separating activity history by session.

## Scope

- Use the current workspace name as the default new-session title.
- Add a prominent session picker alongside the transcript title, while retaining the management sheet for bulk management.
- Store the originating session ID on activity records and render activity in session sections.

## Non-Goals

- No server-side session rename API.
- No persistent activity-history store or changes to activity retention.
- No restructuring of workspace management.

## Implementation Tasks

- [x] Pass a workspace-derived title through `AppState` to `OpenCodeClient.createSession`; cover it with a request test. (`#68c87fd`)
- [x] Add a native session selection control near the transcript title and keep the toolbar management affordance. (`#8d52549`)
- [x] Add a session ID to activity records, attach it at all event sources, and group the inspector by current session title. (`#b68c8f6`)

## Acceptance Criteria

1. A new session is named after its workspace instead of the generic placeholder.
2. A user can create a session and select another session from the transcript surface without opening the management sheet.
3. Activity shows distinct sections for each session, with unlabeled runtime events in a separate general section.
4. Existing prompt, activity, and workspace persistence tests remain green, with focused coverage for the new title and grouping logic.

## Rationale

The workspace is the only stable, user-recognizable context available before the first prompt. A transcript-local picker keeps frequent session switching adjacent to the content it changes, while the management sheet remains the place for recents and bulk browsing. Session IDs, rather than titles, preserve grouping correctness when names collide.
