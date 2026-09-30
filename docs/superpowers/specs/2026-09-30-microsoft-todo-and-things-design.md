# Sticky Calendar — Microsoft To Do and Things Sources Design

Date: 2026-09-30
Status: approved in conversation, pending written-spec review

## Purpose

Add two reminder sources next to Apple Reminders, Todoist, TickTick and Obsidian:
**Microsoft To Do** (through Microsoft Graph) and **Things 3** (through its scripting
interface on the same Mac). Everything the reminders view does today (Today and Lists,
tick and untick, add, edit, postpone, delete, undo and redo, repeating tasks, compact mode)
works with both, within what each service can store.

### Success criteria

- Choosing Things in the source chooser shows the same to-dos as Things' own Today and
  project lists, and ticking, adding, rescheduling and deleting in Sticky Calendar show up
  in Things (and back, within 30 seconds or on ⌘R).
- Signing in to Microsoft To Do takes one browser round trip, survives app restarts, and
  stays signed in (the login token renews itself); a refused login leads straight back to
  "Sign in again".
- No new package dependencies; no client secret in the app.
- Nothing that can't work yet is visible: the Microsoft row stays hidden until the app has a
  registration ID.

### Decisions (from the user)

| Topic | Decision |
|---|---|
| Services | Microsoft To Do and Things now; Google Tasks later maybe; Any.do not (no official API) |
| Things' date | "When" is the due date, so Today matches Things' Today; deadlines are a label |
| Microsoft sign-in | Our own browser sign-in (OAuth 2 authorization code + PKCE, loopback redirect), not MSAL |
| Things access | AppleScript's JavaScript form (JXA), read in bulk; not the database, not the URL scheme |
| Testing | No real accounts yet: fakes and documented examples now, a real-account checklist later |

### Out of scope

- Google Tasks, Any.do.
- Editing Things deadlines, checklists, headings, tags, "This Evening" and reminder times.
- Moving a task between lists (neither source's editor offers it; To Do changes the task's id).
- Microsoft publisher verification.
- Reading Things' SQLite database.

## Shared changes

- `ReminderProvider` gains `.microsoftToDo` ("Microsoft To Do") and `.things` ("Things").
  `ReminderSettings`' source construction and the chooser learn both.
- `ReminderItem` gains `deadline: Date?`, set only by Things; nil elsewhere.
- `ReminderSource` gains `supportsTime` and `supportsPriority` (default true), like the
  existing `canEditNotes`. Things returns false for both; the editor hides the Time toggle
  and the importance picker, and the store never writes a time or importance to a source
  that lacks them (postpone's "+1 h" and "+3 h" are hidden in the editor and the menu
  there).
- The source chooser lists Things greyed out, with "Things isn't installed", when no app
  with bundle id `com.culturedcode.ThingsMac` is installed, and lists Microsoft To Do only
  when `MicrosoftAuth.clientID` is set.
- The reminders list shows a deadline label ("Deadline Fri", red once missed) after the due
  label.
- `RemoteClient` learns (a) a token provider instead of a fixed token, retrying a request
  once after a 401 with a fresh token, (b) GETs of absolute URLs (Graph's `@odata.nextLink`),
  and (c) waiting once for `Retry-After` on a 429 before reporting an error.
- Info.plist's `NSAppleEventsUsageDescription` adds Things: "Sticky Calendar opens Calendar
  on the day you're viewing, and reads and changes your Things to-dos when Things is your
  reminders source."

## Microsoft To Do

### Registration (the owner, once)

In Microsoft Entra (free), register an app for "Accounts in any organizational directory and
personal Microsoft accounts"; add platform "Mobile and desktop applications" with redirect
`http://localhost`; set "Allow public client flows" to Yes. The Application (client) ID goes
into `MicrosoftAuth.clientID` (it is not a secret). The steps go into RELEASING.md. Until the
ID is set (empty string), the chooser does not list Microsoft To Do.

The consent screen shows the app as unverified; personal accounts can consent, some work or
school tenants require an admin to approve unverified apps.

### Sign-in (`MicrosoftAuth`, `LoopbackRedirect`)

1. The chooser's **Sign in with Microsoft** starts `LoopbackRedirect` on a random free port,
   listening on both 127.0.0.1 and ::1, and opens the default browser at
   `https://login.microsoftonline.com/common/oauth2/v2.0/authorize` with `client_id`,
   `response_type=code`, `redirect_uri=http://localhost:<port>`, `scope=Tasks.ReadWrite
   offline_access`, a PKCE `code_challenge` (S256) and a random `state`.
2. The chooser shows "Finish signing in in your browser…" and Cancel.
3. `LoopbackRedirect` accepts one request: it checks `state`, takes `code` (or `error`),
   answers with a small page ("Signed in to Sticky Calendar. You can close this tab." or the
   error) and stops. It also stops on Cancel or after 5 minutes.
4. `MicrosoftAuth` exchanges the code at `.../common/oauth2/v2.0/token` (with the PKCE
   verifier, no secret) and keeps the access token and its expiry in memory and the refresh
   token in the keychain (`ReminderTokens`, account `microsoftToDo`).
5. As for Todoist, one real fetch is made before the source is saved.

Renewal: before a request, if the access token expires within 5 minutes, or after a 401,
`MicrosoftAuth` renews it with the refresh token and saves the refresh token it gets back
(Microsoft replaces it on every use). `invalid_grant` (expired after ~90 days unused,
revoked, password changed) makes the source report `.denied`, and the chooser reopens at
Microsoft with **Sign in again**. Choosing another source deletes the stored token.

### Mapping (`MicrosoftToDoSource`)

- Lists: `GET /me/todo/lists` (following `@odata.nextLink`). `wellknownListName ==
  defaultList` is the default list; `flaggedEmails` is shown read-only. Colours come from a
  fixed palette, by the list's position.
- Tasks, per list, at most 4 lists at a time: open tasks
  (`$filter=status ne 'completed'`) and tasks completed since the start of today
  (`$filter=completedDateTime/dateTime ge '…'`), following `@odata.nextLink`. If Graph
  rejects the filter (to be checked with a real account), fetch all and filter here.
- Due date: `dueDateTime` carries a day only. If the reminder is on
  (`isReminderOn`) and `reminderDateTime` falls on the due day, or there is no due day, the
  task is due at the reminder's time; otherwise it is due on the day, without a time.
- Writing a due date: with a time → `dueDateTime` (that day) and `reminderDateTime` (that
  time) with `isReminderOn: true`; without a time → `dueDateTime` only, an existing reminder
  left alone; none → `dueDateTime: null`. Only changed fields are sent (as `TodoistSource`
  does, via `KnownTasks`).
- Importance: `low` ↔ low, `normal` ↔ none, `high` ↔ high; medium is written as high.
- Notes: `body.content`, written as `contentType: text`.
- Status: `completed` is done (ticked); `notStarted`, `inProgress`, `waitingOnOthers` and
  `deferred` are open. Tick → `completed`, untick → `notStarted`.
- Repeating: `recurrence != null` sets `isRepeating`.
- Link: To Do on the web for the task (format to be confirmed with a real account); if
  unknown, To Do's web home.
- Create `POST …/tasks`, update `PATCH …/tasks/{id}` (the response is taken as the saved
  state), delete `DELETE …/tasks/{id}`.

## Things

### Access (`ThingsScripting`, `ThingsSource`)

`ThingsSource` talks to Things through a `ThingsScripting` protocol. The real implementation
runs JXA scripts via OSAKit off the main thread with a 20-second limit; each read is one
script that fetches every property in bulk (e.g. `Things.toDos.whose({status: 'open'}).name()`)
and returns one JSON string. Writes are small scripts addressing a to-do by id.

When Things is not running, the first load starts it in the background (not activated).
If the user quits Things later, the 30-second checks don't restart it; the view keeps the
last list and says "Things is closed · Open Things"; ⌘R opens it.

The first script triggers macOS's Automation prompt. Error −1743 (not allowed) reports
`.denied`; the chooser then explains how to allow it and opens System Settings → Privacy &
Security → Automation.

### Mapping

- Lists: Inbox, then each open project, then each area's to-dos outside projects, with
  colours from a fixed palette. New to-dos go to the Inbox by default.
- Reminders: every open to-do and those completed since the start of today (Logbook), read
  in bulk: id, name, notes, status, activation date ("When"), due date (deadline),
  completion date, project, area, and whether it's in the Inbox.
- Due date = "When", without a time. A "When" before today is reported as today (Things
  rolls it into Today); "This Evening" counts as today. No "When" = undated (Anytime,
  Someday).
- Deadline = `due date`; shown as a label, not editable here.
- Tick → status completed; untick → status open. Rename, notes → set the property.
  Due date → `schedule … for <date>`, none → move to Anytime. Create → `make new to do` in
  the Inbox or the project, then schedule. Delete → `delete` (to Things' Trash).
- Repeating: Things creates the next copy itself; whether copies are recognisable as
  repeating is to be checked; until then `isRepeating` is false.
- Link: `things:///show?id=<id>`.

### Polling

A 30-second timer reloads the Things source while reminders are showing and Things is
running, skipping a round while the previous read is still going. ⌘R reloads at once.

## Errors

| Situation | Behaviour |
|---|---|
| No network (To Do) | "Couldn't reach Microsoft To Do: …" in the error banner |
| Access token expired | Renewed and the request retried once, silently |
| Refresh refused (`invalid_grant`) | Source `.denied`; chooser at "Sign in again" |
| 429 | Wait `Retry-After` once, retry; then an error |
| Task gone (404) | "The reminder no longer exists", then reload (as today) |
| Things not allowed | Chooser's how-to-allow screen |
| Things quit | Last list stays; "Things is closed · Open Things" |
| Things script times out | "Things didn't answer"; the next check tries again |

The store's existing behaviour applies unchanged: refreshes that began before a change are
ignored, ticked repeats stay ticked until the day changes, undo and redo.

## Testing

Automated (no accounts needed):

- `MicrosoftAuth`: authorize URL parameters (client, scopes, redirect, S256 challenge,
  state); code exchange and renewal store the returned refresh token; `invalid_grant` →
  denied; state mismatch refused. Against `StubHTTP`.
- `LoopbackRedirect`: a real local request returns the code and the page; wrong state and
  `error=` refused; time limit.
- `MicrosoftToDoSource` against stubbed Graph responses modelled on Microsoft's documented
  examples: lists and paging, both due-date cases, importance both ways, only changed fields
  sent, 401 → renew → retry, 429 → wait → retry, Flagged email read-only.
- `ThingsSource` against a fake `ThingsScripting`: past "When" shown as today, deadlines,
  Inbox / projects / areas, tick / untick / create / schedule / delete send the right
  commands, denied / closed / timeout errors.
- Store: a source without times or importance never receives them.

Real-account checklist (when available):

- To Do: full sign-in with a personal account; web link format; `$filter` on status and
  completion date; ticking a repeating task (same id advancing, or a new task); notes saved
  as plain text; Flagged email read-only.
- Things: the bulk JXA read against the real app, and its speed with a few hundred to-dos;
  scripting id = link id; untick via status open; finding the Inbox with Things in another
  language; how repeating copies look.

## Rollout

- Things ships when its tests pass, labelled "(beta)" in the chooser until checked with the
  real app.
- Microsoft To Do ships built and tested but hidden until the client ID is set.
- RELEASING.md gets the Entra registration steps; CHANGELOG.md notes both sources.
