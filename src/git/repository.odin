package git

import "core:os"
import "core:strings"

import "src:model"

inspect_repository :: proc(root_path: string, scan_root: string, allocator := context.allocator) -> model.Repository {
	repo := model.Repository {
		root_path              = strings.clone(root_path, allocator) or_else root_path,
		scan_state             = .Inspecting,
		worktree_state         = .Unknown,
		remote_state           = .Unknown,
		last_checked_unix_time = now_unix(),
	}

	rel, err := os.get_relative_path(scan_root, root_path, allocator)
	if err == nil {
		repo.relative_path = rel
	} else {
		repo.relative_path = strings.clone(root_path, allocator) or_else root_path
	}
	if len(repo.relative_path) == 0 {
		repo.relative_path = strings.clone(".", allocator) or_else "."
	}

	status_res := run(root_path, {"status", "--porcelain=v2", "--branch"}, allocator)
	if !status_res.ok {
		repo.scan_state = .Error
		repo.remote_state = .Git_Error
		repo.worktree_state = .Unknown
		msg := status_res.stderr
		if len(msg) == 0 do msg = status_res.error_message
		repo.error_message = strings.clone(strings.trim_space(msg), allocator) or_else ""
		repo.local_branch_count = count_local_branches(root_path, allocator)
		return repo
	}

	info := parse_porcelain_v2(status_res.stdout, allocator)
	repo.current_branch = info.current_branch
	repo.upstream_branch = info.upstream_branch
	repo.has_staged_changes = info.has_staged_changes
	repo.has_unstaged_changes = info.has_unstaged_changes
	repo.has_untracked_files = info.has_untracked_files
	repo.has_conflicts = info.has_conflicts
	repo.worktree_state = derive_worktree_state(info)

	upstream, ahead, behind, up_ok := query_upstream_divergence(root_path, allocator)
	if len(repo.upstream_branch) == 0 && len(upstream) > 0 {
		delete(repo.upstream_branch)
		repo.upstream_branch = strings.clone(upstream, allocator) or_else ""
	}
	if !info.has_branch_ab && up_ok {
		info.ahead_count = ahead
		info.behind_count = behind
		info.has_branch_ab = true
	}

	repo.remote_state, repo.ahead_count, repo.behind_count = derive_remote_state(info, up_ok, upstream)
	repo.local_branch_count = count_local_branches(root_path, allocator)
	repo.scan_state = .Ready
	return repo
}
