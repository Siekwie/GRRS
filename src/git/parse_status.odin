package git

import "core:strconv"
import "core:strings"

import "src:model"

Status_Info :: struct {
	current_branch:       string,
	upstream_branch:      string,
	is_detached:          bool,

	has_staged_changes:   bool,
	has_unstaged_changes: bool,
	has_untracked_files:  bool,
	has_conflicts:        bool,

	ahead_count:          int,
	behind_count:         int,
	has_branch_ab:        bool,
}

parse_porcelain_v2 :: proc(output: string, allocator := context.allocator) -> Status_Info {
	info: Status_Info

	for line in strings.split_lines(output, context.temp_allocator) {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 do continue

		if strings.has_prefix(trimmed, "# branch.head ") {
			head := trimmed[len("# branch.head "):]
			if head == "(detached)" {
				info.is_detached = true
			} else {
				info.current_branch = strings.clone(head, allocator) or_else ""
			}
			continue
		}

		if strings.has_prefix(trimmed, "# branch.upstream ") {
			up := trimmed[len("# branch.upstream "):]
			info.upstream_branch = strings.clone(up, allocator) or_else ""
			continue
		}

		if strings.has_prefix(trimmed, "# branch.ab ") {
			rest := strings.trim_space(trimmed[len("# branch.ab "):])
			parts := strings.fields(rest, context.temp_allocator)
			for part in parts {
				if len(part) < 2 do continue
				sign := part[0]
				val, ok := strconv.parse_int(part[1:])
				if !ok do continue
				switch sign {
				case '+':
					info.ahead_count = val
				case '-':
					info.behind_count = val
				}
			}
			info.has_branch_ab = true
			continue
		}

		if trimmed[0] == '?' {
			info.has_untracked_files = true
			continue
		}

		if trimmed[0] == 'u' {
			info.has_conflicts = true
			continue
		}

		if trimmed[0] == '1' || trimmed[0] == '2' {
			fields := strings.fields(trimmed, context.temp_allocator)
			if len(fields) < 2 do continue
			xy := fields[1]
			if len(xy) >= 1 && xy[0] != '.' && xy[0] != '?' {
				info.has_staged_changes = true
			}
			if len(xy) >= 2 && xy[1] != '.' && xy[1] != '?' {
				info.has_unstaged_changes = true
			}
			if strings.contains(string(xy), "DD") || strings.contains(string(xy), "AU") ||
			   strings.contains(string(xy), "UD") || strings.contains(string(xy), "UA") ||
			   strings.contains(string(xy), "DU") || strings.contains(string(xy), "AA") ||
			   strings.contains(string(xy), "UU") {
				info.has_conflicts = true
			}
		}
	}

	return info
}

derive_worktree_state :: proc(info: Status_Info) -> model.Repo_Worktree_State {
	if info.has_conflicts do return .Conflicted
	if info.has_unstaged_changes do return .Modified
	if info.has_staged_changes do return .Staged
	if info.has_untracked_files do return .Untracked
	return .Clean
}

derive_remote_state :: proc(info: Status_Info, upstream_ok: bool, upstream: string) -> (
	state: model.Repo_Remote_State,
	ahead: int,
	behind: int,
) {
	ahead = info.ahead_count
	behind = info.behind_count

	if info.is_detached do return .Detached_Head, ahead, behind

	if len(info.upstream_branch) == 0 && !upstream_ok && len(upstream) == 0 {
		return .No_Upstream, ahead, behind
	}

	if info.has_branch_ab {
		if ahead == 0 && behind == 0 do return .Up_To_Date, ahead, behind
		if ahead > 0 && behind == 0 do return .Ahead, ahead, behind
		if ahead == 0 && behind > 0 do return .Behind, ahead, behind
		if ahead > 0 && behind > 0 do return .Diverged, ahead, behind
	}

	if len(info.upstream_branch) > 0 || len(upstream) > 0 {
		return .Unknown, ahead, behind
	}

	return .No_Upstream, ahead, behind
}
