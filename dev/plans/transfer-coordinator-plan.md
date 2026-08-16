# Transfer Coordinator plan: one safety policy, enforced where transfers actually run

**Status:** proposed (design). **Closes:** hardening audit [H-03](../backlog/hardening-audit-2026-07-15.md) (P0), [H-02](../backlog/hardening-audit-2026-07-15.md) (P0), and the H-04 hook for a reviewable dry run.
**Owner interface:** a new `TransferCoordinator` in `app/lib/src/state/` — the ONE door to [`TransferService`](../../app/lib/src/state/transfer_service.dart).
**Reuses:** [`showCopyConflictDialog`](../../app/lib/src/ui/copy_conflict_dialog.dart) · [`planPaste`/`name_conflict.dart`](../../app/lib/src/state/name_conflict.dart) · [`JobsController`](../../app/lib/src/state/jobs_controller.dart) queue · [`TransferOptions`](../../app/lib/src/state/transfer_service.dart)

---

## 1. The problem, stated exactly

The audit's diagnosis is that **safety rules live in scattered UI entry points instead of at execution
boundaries**. Concretely, as of this plan:

`showCopyConflictDialog` has **exactly one caller** — `paste_action.dart`. Every other route to a
transfer calls `TransferService.transfer()` directly and cannot prompt, because it never looks:

| Entry point | File | Prompts on collision? |
| :--- | :--- | :--- |
| Paste / drag-drop | `ui/paste_action.dart` | **yes** — the only one |
| "Copy to…" picker | `ui/browser_pane.dart` `_copyToPicker` | no |
| "Move to…" picker | `ui/browser_pane.dart` `_moveToPicker` | no |
| Download (context menu) | `ui/browser_pane.dart` `_download` | no |
| Upload | `ui/browser_pane.dart` | no |
| Quick dual-pane transfer | `ui/browser_pane.dart` | no |
| Inspector download | `ui/inspector_panel.dart` | no |
| Mobile multi-select actions | `ui/selection_actions.dart` | no |
| Scheduled task | `state/scheduler_controller.dart` | no (and no destructive confirm) |
| Headless `--run-task` | `headless/headless_runner.dart` | no (and no destructive confirm) |

"Copy to…" a folder that already holds that name overwrites it, silently, today.

**One fail-open is already fixed** (commit preceding this plan): an unreadable destination in
`paste_action.dart` used to collapse to an empty name set — reading as "no collisions" — and dispatch
a plain overwrite. It now refuses and says why, with tests. That fix is deliberately narrow; it does
not generalise, which is the point of this plan.

---

## 2. Design

### 2.1 One door

```dart
// state/transfer_coordinator.dart
final transferCoordinatorProvider = Provider<TransferCoordinator>(...);

class TransferCoordinator {
  /// The ONLY sanctioned way to start a transfer. Runs preflight, resolves
  /// conflicts by [policy], enforces destructive limits, then dispatches.
  Future<TransferOutcome> run(TransferRequest request);
}
```

`TransferRequest` carries source/destination/type/items plus a **`ConflictPolicy`**:

| Policy | Who uses it | Behaviour |
| :--- | :--- | :--- |
| `ask(BuildContext)` | every interactive UI path | preflight-lists, prompts once for the batch, applies Skip/Replace/Keep-both |
| `skipExisting` | unattended default | never overwrites; reports what it skipped |
| `replace` | explicit, persisted approval only | overwrites |

`TransferOutcome` returns **per-item results** (transferred / skipped / renamed / failed), which the
audit asks for and which the jobs panel can render instead of one opaque row.

### 2.2 Fail closed is a property of preflight, not of each caller

Preflight lists the destination once. If it cannot, `run()` returns `TransferOutcome.blocked` with a
reason and dispatches nothing — for every entry point, not just paste. Callers render the reason;
they do not get to decide the policy.

### 2.3 Enforce semantics in the rclone request, not only in a cached listing

This is the subtle half of H-03, and the reason "just call the dialog from more places" is not the
fix. A pre-listing is a **snapshot**: between the list and the copy, the destination can change, so a
UI-side decision alone is racy. Where rclone can enforce the same intent server-side, pass it:

| Intent | rclone enforcement |
| :--- | :--- |
| Skip existing | `--ignore-existing` on the request |
| Keep both | rename resolved by `name_conflict.dart`, then a plain copy of a name that cannot collide |
| Replace | default overwrite — the only mode that needs the prompt to have been answered |
| Never clobber newer | `--update` where the mode allows it |

The listing then decides *what to ask*, and the flags decide *what is allowed to happen*.

### 2.4 Unattended work is a different trust level

Scheduled and headless runs have no user to prompt, so they get:

- **`skipExisting` by default** — an unattended job must not overwrite unless someone said so.
- **Destructive runs require persisted approval.** A saved one-way Sync (which deletes at the
  destination) may only run unattended if its task record carries an explicit approval flag, set when
  the user saved it. No flag → the run refuses and records why in the job row.
- **A conservative `--max-delete` floor.** An empty MaxDelete field currently means *no cap*; for
  unattended runs it must mean a default cap, not unlimited.

### 2.5 Cancel becomes honest (H-02)

Fold in the cancel race, because it lives in the same dispatch path: model `starting` /
`cancelRequested` / `canceled` explicitly; after a kickoff returns, re-check terminal state and
immediately stop a job ID that arrived for an already-cancelled row; never report "cancelled" until
termination is confirmed; treat a failed stop as a failure, not a success.

---

## 3. Sequencing

Each step ships and is verifiable on its own. Do **not** start step 2 before step 1's tests exist.

1. **Coordinator + preflight + policy, with paste as its first caller.** No behaviour change for
   paste; it just moves behind the door. Adversarial tests land here.
2. **Migrate the six interactive `browser_pane` / `inspector_panel` / `selection_actions` sites.**
   Mechanical once step 1 is right. Expect UI churn only at call sites — resist restructuring
   `browser_pane.dart` (83KB) or `home_screen.dart` (61KB) in this pass; the audit warns against
   mechanical splits of exactly these files.
3. **Cancel-state machine (H-02)**, including archive subprocess reaping.
4. **Unattended policy** for `scheduler_controller` + `headless_runner`, with the approval flag
   migrated into saved tasks (existing saved tasks default to *not approved* — a deliberate,
   announced one-time prompt rather than silently inheriting permission).
5. **Per-item outcomes surfaced** in the jobs panel — the visible payoff, and the natural seam for
   H-04's reviewable dry-run change set to plug into.

---

## 4. Adversarial tests (the audit requires these, not coverage percentages)

- Destination listing throws → nothing dispatched, reason surfaced. *(exists for paste; must hold for
  every entry point)*
- Destination gains a colliding file **between** preflight and dispatch → the rclone flag prevents
  the clobber even though the snapshot said otherwise.
- "Keep both" against a destination that already holds the renamed candidate too.
- Cancel fired **before** the rclone job ID arrives → late ID is stopped, job reports cancelled only
  after confirmed termination; a stop that fails reports failure.
- Scheduled destructive sync without the approval flag → refuses, records why, deletes nothing.
- Unattended run with an empty MaxDelete → capped, not unlimited.
- Batch where item 3 of 5 fails → outcome reports 2 transferred, 1 failed, 2 continued (no silent
  abort of the batch, no reporting the whole batch as success).

---

## 5. Risks and non-goals

- **Blast radius.** Every transfer in the app moves behind one call. The mitigation is sequencing:
  paste first (already tested), then one call site at a time, each with its own test.
- **Prompt fatigue is a real failure mode.** One prompt per batch, never per item; a clean
  destination must stay silent. The "no collision still transfers" test guards this directly.
- **Not in scope:** redesigning the conflict dialog, splitting the large UI files, the reviewable
  dry-run change set (H-04 — plan separately, but leave the seam in step 5), and anything touching
  the engine lifecycle.
- **Uncertain:** whether every intent maps cleanly onto rclone flags for *every* backend (some
  backends ignore `--update` semantics). Where a flag is unavailable, preflight remains the only
  guard and the outcome must say so rather than imply enforcement it does not have.
