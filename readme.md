# Application plan: Odin Git Repository Scanner

## Goal

A desktop GUI app that:

1. Prompts the user to select a folder on startup.
2. Uses that folder as the scan root.
3. Recursively finds Git repositories below it.
4. Displays a compact repository list:
   - Root folder at the top
   - One row per repository
   - Relative path/name
   - Git working-tree status
   - Ahead/behind/up-to-date status against upstream/origin
   - Local branch count

Sorting folders are traversed but are not shown as repository rows unless they are Git
repositories themselves.

---

## Suggested UX

### Initial screen

On application launch:

```text
┌───────────────────────────────────────────────┐
│ Git Repository Scanner                         │
│                                               │
│             [ Select scan folder ]            │
│                                               │
│ Or paste a path: [                     ] Open │
└───────────────────────────────────────────────┘
```

A native folder picker is preferable, with a text path fallback.

---

### Scan result screen

```text
Root: /home/user/projects
Repos: 24     Scanning complete     [Rescan] [Fetch all] [Change root]

┌─────────────────────────────────────────────────────────────────────┐
│ Repository                  Working tree       Remote       Branches │
├─────────────────────────────────────────────────────────────────────┤
│ api/service-a               ● Clean            ↑ 2           4      │
│ web/dashboard               ● Modified         ✓ Up to date  7      │
│ experiments/parser          ● Clean            ↓ 3           2      │
│ archive/old-project         ● Untracked files  No upstream   1      │
│ tooling/cli                 ● Clean            Detached      5      │
└─────────────────────────────────────────────────────────────────────┘
```

Recommended row fields:

| Field        | Meaning                                                    |
| ------------ | ---------------------------------------------------------- |
| Repository   | Path relative to selected root                             |
| Working tree | Clean, modified, staged, untracked, conflicted             |
| Remote state | Up to date, ahead, behind, diverged, no upstream, detached |
| Branches     | Local branch count                                         |
| Last checked | Optional timestamp                                         |
| Actions      | Open folder, open terminal, refresh one repo               |

Use colors plus text/icons, never color alone:

- Green: clean / up to date
- Yellow: local modifications / ahead
- Red: conflicts / behind / Git error
- Gray: no upstream, detached HEAD, inaccessible repository
- Blue: currently scanning

---

# Core behavior

## 1. Folder selection

At startup, the user selects a folder.

Store the most recently selected root locally, then offer:

```text
Open previous root: /home/user/projects
[Open] [Choose another folder]
```

Do not automatically rescan a previous root without making the behavior clear.

---

## 2. Repository discovery

The scanner recursively walks the selected root.

A directory is considered a potential repository when it contains a `.git` entry:

- `.git` directory: regular Git repository
- `.git` file: worktree/submodule-style repository

Then verify it using Git:

```bash
git -C <path> rev-parse --show-toplevel
```

This prevents false positives and correctly resolves worktrees.

### Traversal rules

- Traverse ordinary folders recursively.
- Never traverse inside `.git` metadata directories.
- Avoid symlink loops.
- Handle permission errors without stopping the overall scan.
- Show inaccessible paths as scan warnings, not fatal errors.
- Support cancellation.
- Skip duplicate resolved repository roots.

### Important decision: nested repositories

Default behavior should be:

- Detect a repository.
- Continue scanning below it for nested repositories.
- Never descend into its `.git` metadata directory.

This finds submodules, example repositories, and repos nested inside monorepos.

Provide a future option:

```text
[ ] Scan for repositories nested inside repositories
```

Default: enabled.

---

# Git inspection

Each discovered repository gets inspected independently.

## Working-tree status

Run:

```bash
git -C <repo> status --porcelain=v2 --branch
```

This is machine-readable and can report:

- Current branch
- Detached HEAD
- Ahead/behind information, if Git knows it
- Staged changes
- Unstaged changes
- Untracked files
- Merge conflicts

Represent the result with an enum-like status:

```odin
Repo_Worktree_State :: enum {
    Clean,
    Modified,
    Staged,
    Untracked,
    Conflicted,
    Unknown,
}
```

A repository may have multiple conditions, so internally use flags rather than relying
only on one display state.

---

## Remote/upstream status

Do not assume every repository uses `origin`.

Use the checked-out branch’s configured upstream:

```bash
git -C <repo> rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
```

Then calculate divergence:

```bash
git -C <repo> rev-list --left-right --count '@{upstream}...HEAD'
```

Output interpretation:

```text
0 0  -> up to date
0 2  -> ahead by 2 commits
3 0  -> behind by 3 commits
3 2  -> diverged: behind 3, ahead 2
```

Possible remote states:

```odin
Repo_Remote_State :: enum {
    Up_To_Date,
    Ahead,
    Behind,
    Diverged,
    No_Upstream,
    Detached_Head,
    Unknown,
    Git_Error,
}
```

### Fetching policy

Do not fetch automatically on every startup.

Fetching may:

- Be slow
- Require credentials
- Trigger network access
- Change remote-tracking references

Instead, show whether the state is based on local remote-tracking data:

```text
Remote status checked against locally known origin/main
Last fetch unknown
```

Provide explicit actions:

```text
[Fetch all remotes] [Fetch this repository]
```

Recommended fetch command:

```bash
git -C <repo> fetch --prune
```

After fetching, rerun the status inspection for that repository.

---

## Branch count

Count local branches with:

```bash
git -C <repo> for-each-ref --format=%(refname:short) refs/heads
```

Count output lines.

Display local branches by default:

```text
Branches: 4
```

A later enhancement can show:

```text
Local: 4   Remote: 9
```

---

# Odin architecture

## Suggested project structure

```text
git-repo-scanner/
├── main.odin
├── app/
│   ├── state.odin
│   ├── actions.odin
│   └── settings.odin
├── scanner/
│   ├── filesystem.odin
│   ├── discovery.odin
│   └── ignore_rules.odin
├── git/
│   ├── commands.odin
│   ├── parse_status.odin
│   ├── repository.odin
│   └── fetch.odin
├── jobs/
│   ├── queue.odin
│   └── worker_pool.odin
├── ui/
│   ├── main_view.odin
│   ├── folder_picker.odin
│   ├── repo_table.odin
│   └── theme.odin
├── platform/
│   ├── file_dialog.odin
│   └── open_path.odin
└── tests/
    ├── status_parser_test.odin
    └── fixture_repositories/
```

---

## Main data model

```odin
Repository :: struct {
    root_path:              string,
    relative_path:          string,

    current_branch:         string,
    upstream_branch:        string,

    worktree_state:         Repo_Worktree_State,
    has_staged_changes:     bool,
    has_unstaged_changes:   bool,
    has_untracked_files:    bool,
    has_conflicts:          bool,

    remote_state:           Repo_Remote_State,
    ahead_count:            int,
    behind_count:           int,

    local_branch_count:     int,

    scan_state:             Repo_Scan_State,
    error_message:          string,
    last_checked_unix_time: i64,
}
```

```odin
App_State :: struct {
    scan_root:          string,
    repositories:       []Repository,

    is_scanning:        bool,
    scan_cancelled:     bool,
    scanned_folders:    int,

    filter_text:        string,
    sort_column:        Sort_Column,
    sort_direction:     Sort_Direction,

    fetch_enabled:      bool,
}
```

---

# Concurrency model

This application is a good fit for Odin’s threading primitives.

## Recommended pipeline

```text
Filesystem scanner
      |
      v
Repository path queue
      |
      v
Git inspection worker pool
      |
      v
Thread-safe result/event queue
      |
      v
Main/UI thread updates visible state
```

### Why this structure

Filesystem walking can discover repositories quickly, while Git commands are slower
because each inspection launches subprocesses and reads repository metadata.

Use a bounded worker pool rather than one thread per repository.

Recommended default:

```text
worker_count = min(cpu_count, 8)
```

For most machines, 4–8 Git workers is enough. Spawning too many `git` processes can
make disk-heavy repositories slower rather than faster.

## UI thread rule

Keep GUI calls on the main thread.

Background workers should only:

- Walk directories
- Run Git commands
- Parse command output
- Send result events to the UI thread

They should not directly modify GUI data structures while rendering.

---

# GUI technology choices

For Odin, a practical approach is:

## Option A: Raylib + immediate-mode UI

Use Odin’s vendored graphics bindings, likely with:

- `vendor:raylib`
- An Odin Dear ImGui binding if available in your preferred ecosystem

This is the fastest route to a polished tool-like UI.

Advantages:

- Easy window creation and rendering
- Good for tables, filters, colored badges, progress indicators
- Suitable for cross-platform desktop utilities
- Fast iteration

## Option B: SDL2 + Dear ImGui

Use SDL2 for window/input/platform behavior and Dear ImGui for the interface.

Advantages:

- Mature desktop windowing path
- Good if you want more control over rendering/platform integration

For this app, prefer an immediate-mode GUI. A repository table, progress display,
filters, and action buttons map naturally to ImGui-style UI.

---

# Folder picker strategy

A true native folder picker is platform-specific.

Implement an abstraction:

```odin
choose_folder :: proc() -> (path: string, ok: bool)
```

Then provide platform implementations:

```text
platform/
├── file_dialog_windows.odin
├── file_dialog_linux.odin
├── file_dialog_macos.odin
└── file_dialog_fallback.odin
```

Fallback behavior: a text field plus an “Open” button.

This lets the rest of the application remain platform-independent.

---

# Scan lifecycle

```text
1. User chooses root directory.
2. Clear previous results.
3. Start filesystem scan worker.
4. UI immediately shows progress.
5. Scanner emits discovered repository paths.
6. Git worker pool inspects repositories in parallel.
7. UI receives incremental repository updates.
8. User can filter/sort while scanning continues.
9. Scan completes or is cancelled.
```

Example progress display:

```text
Scanning: 1,842 folders visited · 17 repositories found · 9 inspected
[Cancel]
```

---

# Sorting and filtering

Useful initial controls:

```text
Search: [ api                  ]
[All] [Dirty] [Behind] [Ahead] [No upstream] [Errors]
Sort: Path | Remote status | Branch count | Last checked
```

Default sort should be relative path ascending.

Useful later sort presets:

- Needs attention first:
  1. Errors
  2. Conflicts
  3. Behind/diverged
  4. Dirty working trees
  5. Everything else
- Alphabetical path
- Most branches
- Most behind

---

# Error handling

A single broken repository must never stop the scan.

Per-repo errors to handle:

- Git is not installed or unavailable
- Directory disappears during scan
- Permission denied
- Invalid `.git` pointer file
- Corrupt Git repository
- Git command timeout
- Repository uses an unsupported Git state
- Fetch requires credentials or fails

Show compact row-level feedback:

```text
archive/legacy-app   Git error: unable to read HEAD
```

A details panel or tooltip can contain the full command error.

Use command timeouts, especially for network fetches.

---

# MVP implementation phases

## Phase 1: Core scanner, no GUI polish

- Select or enter a root path
- Recursively find directories containing `.git`
- Show discovered paths in a basic list
- Handle inaccessible folders and cancellation

Success criterion: reliably discovers repositories without freezing the UI.

## Phase 2: Git metadata

For every repository, collect:

- Branch name
- Dirty/clean status
- Ahead/behind counts
- Local branch count
- Error message when inspection fails

Success criterion: rows show accurate repository state.

## Phase 3: Concurrent scanning

- Add bounded worker pool
- Incrementally update UI
- Add scan progress and cancellation
- Ensure all UI updates happen on the main thread

Success criterion: large roots remain responsive.

## Phase 4: Usable GUI

- Folder picker
- Repository table
- Status badges
- Search/filter/sort
- Rescan
- Per-repository refresh

Success criterion: daily-use ready.

## Phase 5: Fetch support and convenience actions

- Fetch one repository
- Fetch all repositories
- Open repository directory
- Open terminal in repository
- Persist selected root and UI preferences

---

# Key implementation decisions

1. Use Git commands rather than manually parsing `.git` internals.
   - More correct for worktrees, submodules, detached heads, unusual remotes, and
     Git configuration.

2. Do not assume `origin`.
   - Prefer the current branch upstream.
   - Show “No upstream” when none is configured.

3. Do not auto-fetch.
   - Remote status is only as current as the last fetch.
   - Fetch should be user-triggered.

4. Treat scanning and inspection as separate jobs.
   - Filesystem traversal discovers work.
   - Git workers inspect work.
   - GUI consumes events.

5. Represent partial results.
   - A repository can be discovered before its Git status has been inspected.

---

# Minimal first milestone

Build this exact vertical slice first:

```text
1. Start app
2. Choose folder
3. Discover Git repositories recursively
4. Show relative paths in a GUI table
5. Run git status --porcelain=v2 --branch for each repository
6. Display clean/dirty and ahead/behind
7. Display local branch count
8. Add Rescan
```

That produces a useful application early, while keeping native dialogs, fetch support,
filters, persistent settings, and advanced actions as later additions.
