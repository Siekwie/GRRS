package ui

import rl "vendor:raylib"

import "src:model"

worktree_color :: proc(state: model.Repo_Worktree_State) -> rl.Color {
	switch state {
	case .Clean:
		return COL_OK
	case .Modified, .Staged, .Untracked:
		return COL_WARN
	case .Conflicted:
		return COL_BAD
	case .Unknown:
		return COL_NEUTRAL
	}
	return COL_NEUTRAL
}

remote_color :: proc(state: model.Repo_Remote_State) -> rl.Color {
	switch state {
	case .Up_To_Date:
		return COL_OK
	case .Ahead:
		return COL_WARN
	case .Behind, .Diverged, .Git_Error:
		return COL_BAD
	case .No_Upstream, .Detached_Head:
		return COL_NEUTRAL
	case .Unknown:
		return COL_NEUTRAL
	}
	return COL_NEUTRAL
}

WINDOW_W :: 1200
WINDOW_H :: 760
HEADER_H :: 52
TOOLBAR_H :: 40
ROW_H :: 30
PAD :: 12

COL_BG :: rl.Color{22, 24, 28, 255}
COL_PANEL :: rl.Color{30, 33, 38, 255}
COL_PANEL2 :: rl.Color{38, 42, 48, 255}
COL_BORDER :: rl.Color{50, 55, 62, 255}
COL_TEXT :: rl.Color{210, 214, 220, 255}
COL_MUTED :: rl.Color{120, 128, 138, 255}
COL_ACCENT :: rl.Color{90, 140, 210, 255}

COL_OK :: rl.Color{100, 170, 120, 255}
COL_WARN :: rl.Color{210, 170, 80, 255}
COL_BAD :: rl.Color{190, 100, 100, 255}
COL_NEUTRAL :: rl.Color{130, 136, 145, 255}
COL_SCAN :: rl.Color{90, 150, 210, 255}
