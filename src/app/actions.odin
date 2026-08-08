package app

import "core:strings"
import "core:os"

import "src:jobs"
import "src:model"

begin_scan :: proc(state: ^model.App_State, session: ^jobs.Scan_Session, root: string) {
	clear_scan_results(state)
	delete(state.scan_root)
	state.scan_root = strings.clone(root, context.allocator) or_else root
	state.is_scanning = true
	state.scan_cancelled = false
	state.scanned_folders = 0
	state.repos_found = 0
	state.repos_inspected = 0
	state.repos_git_queued = 0
	state.scroll_y = 0
	state.screen = .Scan_Results
	delete(state.status_message)
	jobs.start_scan(session, state.scan_root, state.scan_nested_repos)
}

clear_scan_results :: proc(state: ^model.App_State) {
	for &repo in state.repositories {
		model.delete_repo_strings(&repo)
	}
	clear(&state.repositories)
	clear(&state.repo_index)
}

cancel_scan :: proc(state: ^model.App_State, session: ^jobs.Scan_Session) {
	state.scan_cancelled = true
	jobs.cancel(session)
}

handle_scan_event :: proc(state: ^model.App_State, event: jobs.Scan_Event) {
	switch event.kind {
	case .Repo_Discovered:
		data := event.data.(jobs.Repo_Discovered_Event)
		repo := model.Repository {
			root_path     = data.root_path,
			relative_path = data.relative_path,
			scan_state    = .Discovered,
		}
		model.upsert_repo(state, repo)

	case .Repo_Inspected:
		data := event.data.(jobs.Repo_Inspected_Event)
		model.upsert_repo(state, data.repository)

	case .Scan_Progress:
		data := event.data.(jobs.Scan_Progress_Event)
		state.scanned_folders = data.folders_visited
		state.repos_found = data.repos_found
		state.repos_inspected = data.repos_inspected
		state.repos_git_queued = data.repos_queued

	case .Scan_Warning:
		data := event.data.(jobs.Scan_Warning_Event)
		delete(state.status_message)
		state.status_message = strings.clone(data.message, context.allocator) or_else ""

	case .Scan_Complete:
		state.is_scanning = false
	}
}

validate_scan_root :: proc(path: string) -> bool {
	trimmed := strings.trim_space(path)
	return len(trimmed) > 0 && os.is_directory(trimmed)
}

set_path_input :: proc(state: ^model.App_State, path: string) {
	state.path_input_len = min(len(path), len(state.path_input) - 1)
	copy(state.path_input[:], path[:state.path_input_len])
}
