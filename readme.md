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

# Concurrency model

This application is a good fit for Odin’s threading primitives.

## Pipeline

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
