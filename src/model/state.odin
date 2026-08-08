package model

Repo_Worktree_State :: enum {
	Clean,
	Modified,
	Staged,
	Untracked,
	Conflicted,
	Unknown,
}

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

Repo_Scan_State :: enum {
	Discovered,
	Inspecting,
	Ready,
	Error,
}

Sort_Column :: enum {
	Path,
	Worktree,
	Remote,
	Branches,
}

Sort_Direction :: enum {
	Asc,
	Desc,
}

Screen :: enum {
	Folder_Select,
	Scan_Results,
}

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

App_State :: struct {
	screen: Screen,

	scan_root:       string,
	path_input:      [512]u8,
	path_input_len:  int,

	repositories:    [dynamic]Repository,
	repo_index:      map[string]int,

	is_scanning:        bool,
	scan_cancelled:     bool,
	scan_nested_repos:  bool,
	scanned_folders:    int,
	repos_found:        int,
	repos_inspected:    int,
	repos_git_queued:   int,
	scan_anim:          f32,

	filter_text:     [256]u8,
	filter_len:      int,

	sort_column:     Sort_Column,
	sort_direction:  Sort_Direction,

	scroll_y:        f32,

	status_message:  string,
}

delete_repo_strings :: proc(repo: ^Repository) {
	delete(repo.root_path)
	delete(repo.relative_path)
	delete(repo.current_branch)
	delete(repo.upstream_branch)
	delete(repo.error_message)
}

init_state :: proc(state: ^App_State) {
	state^ = {}
	state.screen = .Folder_Select
	state.sort_column = .Path
	state.sort_direction = .Asc
	state.scan_nested_repos = false
	state.repo_index = make(map[string]int)
}

destroy_state :: proc(state: ^App_State) {
	for &repo in state.repositories {
		delete_repo_strings(&repo)
	}
	delete(state.repositories)
	delete(state.status_message)
	delete(state.scan_root)
	delete(state.repo_index)
}

find_repo :: proc(state: ^App_State, root_path: string) -> (^Repository, bool) {
	idx, ok := state.repo_index[root_path]
	if !ok do return nil, false
	return &state.repositories[idx], true
}

upsert_repo :: proc(state: ^App_State, repo: Repository) -> ^Repository {
	if existing, ok := find_repo(state, repo.root_path); ok {
		delete_repo_strings(existing)
		existing^ = repo
		return existing
	}
	append(&state.repositories, repo)
	idx := len(state.repositories) - 1
	state.repo_index[repo.root_path] = idx
	return &state.repositories[idx]
}
