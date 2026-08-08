package ui

import "core:fmt"
import "core:strings"
import "core:slice"

import "src:model"

Repo_Table_Action :: enum {
	None,
	Rescan,
	Change_Root,
	Cancel_Scan,
}

Repo_Table_Result :: struct {
	action: Repo_Table_Action,
}

draw_repo_table :: proc(state: ^model.App_State) -> Repo_Table_Result {
	result: Repo_Table_Result

	w := rl.GetScreenWidth()
	h := rl.GetScreenHeight()

	// Header bar
	draw_rect(0, 0, w, HEADER_H, COL_PANEL)
	header := fmt.tprintf("Root: %s", state.scan_root)
	draw_text(header, PAD, 10, FONT_BODY, COL_TEXT)

	status := "Scanning complete"
	if state.is_scanning {
		status = fmt.tprintf(
			"Scanning: %d folders · %d repos · %d inspected · %d git queued",
			state.scanned_folders,
			state.repos_found,
			state.repos_inspected,
			state.repos_git_queued,
		)
	}
	draw_text(status, PAD, 32, FONT_SMALL, state.is_scanning ? COL_SCAN : COL_MUTED)

	btn_y: i32 = 8
	btn_h: i32 = 32
	x := w - PAD

	if button("Change root", x - 110, btn_y, 110, btn_h).pressed {
		result.action = .Change_Root
	}
	x -= 118

	if state.is_scanning {
		if button("Cancel", x - 80, btn_y, 80, btn_h).pressed {
			result.action = .Cancel_Scan
		}
		x -= 88
	} else if button("Rescan", x - 80, btn_y, 80, btn_h).pressed {
		result.action = .Rescan
	}

	// Toolbar
	toolbar_y: i32 = HEADER_H
	draw_rect(0, toolbar_y, w, TOOLBAR_H, COL_PANEL2)
	draw_text("Search:", PAD, toolbar_y + 10, FONT_SMALL, COL_MUTED)
	filter_buf: [512]u8
	copy(filter_buf[:], state.filter_text[:])
	filter_len := state.filter_len
	text_input(&filter_buf, &filter_len, PAD + 64, toolbar_y + 4, 260, 28, "filter repositories")
	state.filter_len = min(filter_len, len(state.filter_text) - 1)
	copy(state.filter_text[:], filter_buf[:state.filter_len])

	count_text := fmt.tprintf("Repos: %d", len(state.repositories))
	draw_text(count_text, PAD + 340, toolbar_y + 10, FONT_SMALL, COL_MUTED)

	// Column headers
	table_y: i32 = toolbar_y + TOOLBAR_H
	draw_rect(0, table_y, w, ROW_H, COL_BORDER)
	col_repo: i32 = PAD
	col_work: i32 = w / 2
	col_remote: i32 = col_work + 180
	col_branches: i32 = col_remote + 200
	draw_text("Repository", col_repo, table_y + 6, FONT_SMALL, COL_MUTED)
	draw_text("Working tree", col_work, table_y + 6, FONT_SMALL, COL_MUTED)
	draw_text("Remote", col_remote, table_y + 6, FONT_SMALL, COL_MUTED)
	draw_text("Branches", col_branches, table_y + 6, FONT_SMALL, COL_MUTED)

	// Collect and filter rows
	indices := make([dynamic]int, context.temp_allocator)
	for i in 0 ..< len(state.repositories) {
		repo := state.repositories[i]
		if !repo_matches_filter(state, repo) do continue
		append(&indices, i)
	}
	sort_repo_indices(state, indices[:])

	body_y := table_y + ROW_H
	body_h := h - body_y
	visible_rows := int(body_h / ROW_H) + 1
	max_scroll := max(0, len(indices) - visible_rows)
	state.scroll_y = clamp(state.scroll_y, 0, f32(max_scroll * ROW_H))

	start_row := int(state.scroll_y / ROW_H)
	if rl.GetMouseWheelMove() != 0 {
		state.scroll_y -= rl.GetMouseWheelMove() * ROW_H
		state.scroll_y = clamp(state.scroll_y, 0, f32(max_scroll * ROW_H))
		start_row = int(state.scroll_y / ROW_H)
	}

	if len(state.repositories) == 0 && state.is_scanning {
		empty_y := body_y + 40
		draw_text("Scanning for Git repositories...", PAD + 8, empty_y, FONT_HEADING, COL_SCAN)
		hint := fmt.tprintf(
			"%d folders visited so far",
			state.scanned_folders,
		)
		draw_text(hint, PAD + 8, empty_y + 30, FONT_BODY, COL_MUTED)
	}

	for row in 0 ..< visible_rows {
		idx := start_row + row
		if idx >= len(indices) do break

		repo := state.repositories[indices[idx]]
		y := body_y + i32(row) * ROW_H - i32(state.scroll_y) % ROW_H
		if y < body_y || y + ROW_H > h do continue

		bg := COL_BG if row % 2 == 0 else COL_PANEL
		draw_rect(0, y, w, ROW_H, bg)

		name_col := repo.scan_state == .Discovered ? COL_SCAN : COL_TEXT
		draw_text(repo.relative_path, col_repo, y + 6, FONT_BODY, name_col)

		work_label, work_col := worktree_label(repo)
		draw_text(work_label, col_work, y + 6, FONT_BODY, work_col)

		remote_label, remote_col := remote_label(repo)
		draw_text(remote_label, col_remote, y + 6, FONT_BODY, remote_col)

		branch_text := fmt.tprintf("%d", repo.local_branch_count)
		draw_text(branch_text, col_branches, y + 6, FONT_BODY, COL_TEXT)
	}

	if state.is_scanning {
		draw_scanning_overlay(state, w, h)
	}

	return result
}

@(private)
draw_scanning_overlay :: proc(state: ^model.App_State, w, h: i32) {
	overlay_h: i32 = 62
	y := h - overlay_h - PAD
	draw_rect(PAD, y, w - PAD * 2, overlay_h, COL_PANEL2)
	rl.DrawRectangleLines(PAD, y, w - PAD * 2, overlay_h, COL_SCAN)

	// Simple animated activity dots.
	dots := "---"
	pulse := int(state.scan_anim) % 4
	switch pulse {
	case 0: dots = ".  "
	case 1: dots = ".. "
	case 2: dots = "..."
	case 3: dots = " .."
	}

	phase := "Walking folders"
	if state.repos_found > 0 && state.repos_inspected < state.repos_found {
		phase = "Inspecting repositories"
	} else if state.repos_found > 0 && state.repos_inspected >= state.repos_found && state.scanned_folders > 0 {
		phase = "Finishing scan"
	}

	line1 := fmt.tprintf("%s %s", phase, dots)
	draw_text(line1, PAD + 12, y + 10, FONT_BODY, COL_TEXT)

	line2 := fmt.tprintf(
		"%d folders visited · %d repositories found · %d inspected · %d in git queue",
		state.scanned_folders,
		state.repos_found,
		state.repos_inspected,
		state.repos_git_queued,
	)
	draw_text(line2, PAD + 12, y + 34, FONT_SMALL, COL_MUTED)
}

@(private)
repo_matches_filter :: proc(state: ^model.App_State, repo: model.Repository) -> bool {
	if state.filter_len == 0 do return true
	needle := strings.to_lower(string(state.filter_text[:state.filter_len]), context.temp_allocator)
	hay := strings.to_lower(repo.relative_path, context.temp_allocator)
	return strings.contains(hay, needle)
}

@(private)
sort_repo_indices :: proc(state: ^model.App_State, indices: []int) {
	slice.sort_by_with_data(indices, proc(i, j: int, user_data: rawptr) -> bool {
		s := cast(^model.App_State)user_data
		a := s.repositories[i]
		b := s.repositories[j]
		less: bool
		switch s.sort_column {
		case .Path:
			less = a.relative_path < b.relative_path
		case .Worktree:
			less = a.worktree_state < b.worktree_state
		case .Remote:
			less = a.remote_state < b.remote_state
		case .Branches:
			less = a.local_branch_count < b.local_branch_count
		}
		return less if s.sort_direction == .Asc else !less
	}, state)
}

@(private)
worktree_label :: proc(repo: model.Repository) -> (label: string, col: rl.Color) {
	switch repo.scan_state {
	case .Discovered, .Inspecting:
		return "Scanning...", COL_SCAN
	case .Error:
		if len(repo.error_message) > 0 {
			return repo.error_message, COL_BAD
		}
		return "Git error", COL_BAD
	case .Ready:
		break
	}

	switch repo.worktree_state {
	case .Clean:
		return "Clean", COL_OK
	case .Modified:
		return "Modified", COL_WARN
	case .Staged:
		return "Staged", COL_WARN
	case .Untracked:
		return "Untracked files", COL_WARN
	case .Conflicted:
		return "Conflicted", COL_BAD
	case .Unknown:
		return "Unknown", COL_NEUTRAL
	}
	return "Unknown", COL_NEUTRAL
}

@(private)
remote_label :: proc(repo: model.Repository) -> (label: string, col: rl.Color) {
	if repo.scan_state != .Ready {
		return "...", COL_NEUTRAL
	}

	switch repo.remote_state {
	case .Up_To_Date:
		return "Up to date", COL_OK
	case .Ahead:
		return fmt.tprintf("Ahead %d", repo.ahead_count), COL_WARN
	case .Behind:
		return fmt.tprintf("Behind %d", repo.behind_count), COL_BAD
	case .Diverged:
		return fmt.tprintf("Diverged +%d -%d", repo.ahead_count, repo.behind_count), COL_BAD
	case .No_Upstream:
		return "No upstream", COL_NEUTRAL
	case .Detached_Head:
		return "Detached", COL_NEUTRAL
	case .Unknown:
		return "Unknown", COL_NEUTRAL
	case .Git_Error:
		return "Git error", COL_BAD
	}
	return "Unknown", COL_NEUTRAL
}

import rl "vendor:raylib"
