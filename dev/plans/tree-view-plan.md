# 📦 Parcel Plan: An optional tree view

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `SHIPPED` — **v0.8**, alongside [scheduling-and-backup-plan.md](scheduling-and-backup-plan.md). Phases A–E built and tested (`ui/tree_view.dart`, `state/tree_state.dart`; `test/tree_state_test.dart`, `test/tree_controller_test.dart`, `test/tree_node_paths_test.dart`). What §4.f wanted that is **not** built, and one thing built that §1 had scoped out, are recorded in Phase 6. |
| **Version** | `v1.1.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-09-09 |

---

## 1️⃣ Phase 1: Expansion & Scoping

**Intent.** Rclone Browser shows one pane as an expandable hierarchy — a row per
entry, a disclosure arrow on every folder, children indented beneath their parent,
with Name / Size / Modified as columns. Several folders are open at once and the
shape of the tree is the navigation. Airclone today shows exactly one folder at a
time, in `ViewMode { list, grid, media }` (`state/browser_controller.dart:15`).

The ask is a **fourth, optional view mode**, not a replacement. The dual-pane
browser stays the default and stays the thing the rest of the app is built around.

**In scope:** a `ViewMode.tree` with lazy per-node expansion; the columns Rclone
Browser shows; expansion state that survives switching modes within a tab;
selection and the existing right-click actions working from a tree node.

**Out of scope for v0.8:**
- **Expand-all / recursive walk.** Rclone Browser's Export does this. On a cloud
  remote it is one `operations/list` per folder and it is how a UI becomes a
  bill. If it ever ships it needs the same consent treatment as the dedupe scan.
- Miller columns. A different view, still unbuilt, and not what was asked for.
- Tree in the mobile shell. A phone has no room for indentation plus three
  columns; the touch shell keeps its own navigation.
- Drag-and-drop *within* the tree. See §5 — the selection model has to settle first.
  *(As shipped this IS built — see Phase 6 — and it is untested.)*

## 2️⃣ Phase 2: Requirements & Context

### 2.1 What exists, and what it assumes

| Piece | Today | What a tree changes |
| :--- | :--- | :--- |
| `BrowserState` | `path` + `entries` — **one flat folder** (`state/browser_controller.dart`) | A tree needs a *forest*: children keyed by folder path, several open at once |
| `ViewMode` | `list, grid, media` | Add `tree`; persisted per remote already (per-remote view memory shipped in a26) |
| Listing | `operations/list` of `state.path` | One call per **expanded node**, lazily, on first expand |
| Pane operations | build a path as `state.path` + entry name | **Must** build from the node's own parent — see §5, this is the sharp edge |
| Conflict preflight | `transferNamesIntoFolder` takes ONE `srcParentPath` + names | A tree selection can span folders; needs grouping, like `_uploadLocal` already does for a multi-folder OS drop |
| Thumbnails | per visible entry, guarded by `wouldHydrateOnRead` | Tree rows are text; no thumbnails, so no hydration surface |

### 2.2 The invariant this feature is most likely to break

`dev/backlog/` and the v0.5.0 history record it, and it is the reason to be
careful here: **pane operations used to build a path as `state.path` + the entry
name, so a stale `entries` list produced a preview 404 or a copy that failed with
"object not found".** The fix was to clear `entries` on navigate and to guard
`_load` against superseded responses.

A tree deliberately holds **many folders' listings at once and does not clear them
on navigate** — which is precisely the condition that invariant was written
against. So:

> **Every operation initiated from a tree node must derive its path from that
> node's own parent, never from `state.path`.** `state.path` in tree mode is the
> root the tree is rooted at, not the folder the row lives in.

This is the single highest-risk item in the plan and the one to write tests for
first.

## 3️⃣ Phase 3: User Clarification

* **Open Questions:**
  - `[x]` **Does the tree replace the pane, or sit beside it?** Rclone Browser
    gives the whole pane to the tree. A separate always-present tree rail (the
    Explorer left pane) is a different feature and a bigger one. Recommendation:
    a view mode, matching the ask. → **Answer: a view mode**, as built —
    `ViewMode.tree`, offered from View ▾ on the desktop shell only.
  - `[x]` **Does expansion state persist across restarts?** Per-remote view mode
    already does. Persisting expansion means storing a set of paths per remote —
    cheap, but a tree that reopens 40 folders costs 40 listings on launch.
    Recommendation: persist within the session only. → **Answer: session only**
    (`TreeState.expanded` is never persisted; it survives switching modes within
    a tab and is dropped when the remote changes).
  - `[x]` **Should a folder's size be shown?** Rclone Browser leaves it blank for
    folders and offers "Get Size" per selection. Computing it eagerly is
    `operations/size` per folder — a recursive walk each, and exactly the mistake
    just fixed in the sync preflight. Recommendation: blank, with an explicit
    per-folder action. → **Answer: blank**, as the flat list already leaves it.
    No per-folder "Get size" action was added.
  - `[x]` **Can a selection span folders?** → **ANSWERED (user, 2026-09-09): yes.**
    So §4.D is in scope and is the largest single piece of this plan. Transfers
    group by source folder — the shape `_uploadLocal` already uses for an OS drop
    spanning several folders — and the conflict preflight asks once per group,
    which is honest because each group is a different source. Delete and the
    other bulk operations need the same treatment, and `state.selected` becomes a
    set of full paths rather than names within one folder.

## 4️⃣ Phase 4: Detailed Execution Plan

- **A — Tree state `[M]`.** A `TreeState` beside the flat one: `Map<String,
  List<RcloneFile>> children` plus `Set<String> expanded`, both keyed by full
  folder path. Lazy: expanding a node with no cached children issues one
  `operations/list` for it. The existing superseded-response guard in `_load`
  must be generalised per node, or two fast expand/collapse cycles can deliver an
  older listing over a newer one.
- **B — The view `[M]`.** A flat `ListView` over a *flattened* tree — do not
  nest scrollables. Each row: disclosure arrow (folders only), icon, name,
  size, modified. Indentation by depth. Reuse the existing row widget where it
  fits rather than forking a second one that drifts.
- **C — Operations from a node `[S]`, and the risky one.** Right-click, rename,
  delete, copy/move all resolve their parent from the node. Tests should assert
  a path built from a *deep* node while `state.path` is the root — that is the
  regression that would otherwise reach a user as "copy says object not found".
- **D — Selection `[M]`.** If a selection may span folders, `transferNamesIntoFolder`
  is called once per source folder, grouped — the same shape `_uploadLocal` uses
  for an OS drop from several folders. The conflict preflight then asks once per
  group, which is the honest answer since each group is a different source.
- **E — Keyboard `[S]`.** Left/Right collapse/expand, Up/Down move, matching what
  a tree is expected to do. The TV D-pad shell already has directional handling
  worth reusing rather than reinventing.

### 4.f What people expect from a tree

- **Type-to-jump** inside the tree, as Explorer and Finder do. Type-to-navigate
  already exists for the flat list; it should follow into the tree rather than
  quietly stop working there.
- **Filter that reveals matches in collapsed folders.** The existing Ctrl+F
  filters the visible listing. In a tree, users expect a filter to *find* things
  they have not expanded — which is a recursive search, not a filter, and is a
  much bigger promise. Either make it clearly a same-level filter, or do not put a
  filter box on the tree at all until search is real.
- **Expand/collapse all under this node**, from the right-click menu — bounded to
  one subtree, which is affordable, unlike a global expand-all.
- **The current folder stays revealed.** Switching from list to tree should open
  the tree to wherever the user already was, not dump them at the root.
- **Show/hide hidden files** honoured the same way the flat list honours it, so
  the two views do not disagree about what exists.
- **The columns sort**, and sorting sorts *within each parent* rather than
  flattening the hierarchy. This is the detail people notice immediately when it
  is wrong.
- **Middle-click or a modifier opens a folder in the other pane** — the dual-pane
  habit does not disappear because the view changed.

## 5️⃣ Phase 5: Risks

- [🚫] **The stale-path invariant above.** It is the one that has already bitten
  this codebase once, and a tree is the structure most likely to bite it again.
- [⚠️] **Expansion cost on cloud remotes.** Every expand is a round trip. A tree
  that auto-expands, remembers 40 open folders, or offers expand-all turns a
  browse into dozens of API calls. Lazy, session-only, no expand-all.
- [⚠️] **Deep indentation at a narrow width.** The name column is what
  distinguishes remotes and folders, and indentation eats it. `OverflowName`
  already handles a name that outgrows its width (v0.7.7); a tree makes that the
  common case rather than the exception, so the row must keep a sane minimum name
  width before it starts indenting further.
- [⚠️] **Two sources of truth for "where am I".** With a tree, the address bar,
  the breadcrumb and the pane title all have to agree on what `state.path` means.
  Decide that before building the view, not after.

## 6️⃣ Phase 6: Implementation Checklist

- `[x]` **A** tree state + lazy per-node load, with a per-node superseded guard
  (`state/tree_state.dart`; `expandNode` / `collapseNode` / `toggleExpand` in
  `state/browser_controller.dart`).
- `[x]` **B** flattened list view with the three columns (`ui/tree_view.dart` —
  one `ListView.builder` over `flattenTree`, indentation capped so the Name
  column keeps 140 px).
- `[x]` **C** node-relative operations, with the deep-node path test written first
  (`test/tree_node_paths_test.dart` — every row carries `TreeRow.parentPath`).
- `[x]` **D** selection, grouped per source folder through the existing preflight
  (`groupByParent`; `TreeState.selected` is a set of full paths, separate from
  the flat `selected`).
- `[x]` **E** keyboard expand/collapse (Up/Down/Home/End, Left/Right, Enter/Space,
  Delete, F2, Ctrl+C / Ctrl+X — `_TreeViewState._onKey`).

### 6.1 What §4.f wanted and what shipped — honestly

Built: the Ctrl+F filter is a **same-level filter over what is loaded** and says
so (`flattenTree(filter:)` keeps an expanded ancestor whose loaded descendant
matches and never opens a collapsed folder); the current folder is where the tree
roots itself (`flattenTree(rootPath: state.path, …)`), so switching list → tree
does not dump the user at the remote's root. Whether hidden files and sort order
are applied per parent exactly as the flat list applies them was not re-verified
when this plan was closed out.

**Not built:**

- **Expand / collapse all under a node.** No such action exists; expansion is
  one folder at a time (arrow, double-click, Right).
- **Middle-click / modifier to open a folder in the other pane.** No tertiary-
  button handling anywhere in the tree; the other pane is reached through the
  existing *Open in other pane* context-menu action
  (`FileMenuAction.openInOtherPane`) only.
- **Type-to-jump follows into the tree only for the root's entries.**
  `_typeaheadJump` in `ui/home_screen.dart` searches `visibleEntries` — the
  root's listing — and `selectOnly` maps the hit onto the top-level tree row. A
  name three levels deep is not found by typing it.

**Built despite §1 scoping it out:** drag-and-drop *within* the tree. Every tree
row is both a drag source (`FileRow.dragData`, carrying the selected rows that
share the dragged row's folder — never rows from another parent) and a drop
target (`onDropInto`, routed through the pane's existing drop path). There is no
test for a drag that starts and ends inside the tree; `tree_node_paths_test`
covers the same path-resolution rule for the other operations, but not this one.

## 7️⃣ Phase 7: Verification

- `[x]` An operation on a node three levels deep resolves against **that node's**
  parent while `state.path` is the root — `test/tree_node_paths_test.dart`
  (rename, delete, and a deep selection that never surfaces through
  `selectedEntries`).
- `[x]` Expanding a folder issues exactly one listing, and collapsing then
  re-expanding issues none (cached) — `test/tree_controller_test.dart`.
- `[x]` A rapid expand/collapse/expand does not render the older listing —
  `test/tree_controller_test.dart` (in-flight and superseded-reload cases).
- `[x]` A selection spanning two folders produces one conflict prompt per source
  folder and copies both correctly — `test/tree_node_paths_test.dart`.
- `[x]` Switching tree → list → tree keeps the expansion set within the session
  — `test/tree_controller_test.dart`.
- `[ ]` A drag from one tree row dropped on another moves the right files into
  the right folder — **no test**; see §6.1.
