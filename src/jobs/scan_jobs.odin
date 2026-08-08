package jobs

import "base:intrinsics"
import "base:runtime"
import "core:os"
import "core:strings"
import "core:sync/chan"
import "core:thread"
import "core:sync"
import "core:time"

import "src:model"
import "src:git"
import "src:scanner"

// Cap simultaneous git inspect workers and queued inspect tasks.
MAX_GIT_WORKERS        :: 5
MAX_INSPECT_OUTSTANDING :: 10

EVENT_BUFFER         :: 512
MAX_EVENTS_PER_FRAME :: 64

Event_Kind :: enum {
	Repo_Discovered,
	Repo_Inspected,
	Scan_Progress,
	Scan_Complete,
	Scan_Warning,
}

Repo_Discovered_Event :: struct {
	root_path:     string,
	relative_path: string,
}

Repo_Inspected_Event :: struct {
	repository: model.Repository,
}

Scan_Progress_Event :: struct {
	folders_visited: int,
	repos_found:     int,
	repos_inspected: int,
	repos_queued:    int,
}

Scan_Warning_Event :: struct {
	message: string,
}

Scan_Complete_Event :: struct {}

Scan_Event :: struct {
	kind: Event_Kind,
	data: Scan_Event_Data,
}

Scan_Event_Data :: union {
	Repo_Discovered_Event,
	Repo_Inspected_Event,
	Scan_Progress_Event,
	Scan_Complete_Event,
	Scan_Warning_Event,
}

Scan_Session :: struct {
	event_chan:        chan.Chan(Scan_Event),
	has_event_chan:    bool,
	cancelled:         bool,
	cancel_mutex:      sync.Mutex,
	scan_root:         string,
	scan_nested_repos: bool,
	seen_roots:        map[string]bool,
	folders_count:     int,
	found_count:       int,
	inspected:         int,
	pool:              thread.Pool,
	pool_ready:        bool,
	allocator:         runtime.Allocator,
}

create_session :: proc(allocator := context.allocator) -> Scan_Session {
	session: Scan_Session
	session.allocator = allocator
	session.seen_roots = make(map[string]bool)
	session.event_chan, _ = chan.create_buffered(chan.Chan(Scan_Event), EVENT_BUFFER, allocator)
	session.has_event_chan = true
	return session
}

destroy_session :: proc(session: ^Scan_Session) {
	if session.pool_ready {
		thread.pool_destroy(&session.pool)
	}
	if session.has_event_chan {
		chan.destroy(session.event_chan)
		session.has_event_chan = false
	}
	delete(session.scan_root)
	delete(session.seen_roots)
}

is_cancelled :: proc(session: ^Scan_Session) -> bool {
	sync.guard(&session.cancel_mutex)
	return session.cancelled
}

cancel :: proc(session: ^Scan_Session) {
	sync.guard(&session.cancel_mutex)
	session.cancelled = true
}

reset :: proc(session: ^Scan_Session, scan_root: string, scan_nested: bool) {
	cancel(session)
	if session.pool_ready {
		thread.pool_destroy(&session.pool)
		session.pool_ready = false
	}
	clear(&session.seen_roots)
	session.cancelled = false
	session.folders_count = 0
	session.found_count = 0
	session.inspected = 0
	session.scan_nested_repos = scan_nested
	delete(session.scan_root)
	session.scan_root = strings.clone(scan_root, session.allocator) or_else scan_root
}

emit :: proc(session: ^Scan_Session, event: Scan_Event) {
	if !session.has_event_chan do return
	if chan.try_send(session.event_chan, event) do return
	if event.kind == .Scan_Progress do return
	_ = chan.send(session.event_chan, event)
}

inspect_outstanding :: proc(session: ^Scan_Session) -> int {
	if !session.pool_ready do return 0
	return thread.pool_num_outstanding(&session.pool)
}

emit_progress :: proc(session: ^Scan_Session) {
	emit(session, Scan_Event {
		kind = .Scan_Progress,
		data = Scan_Progress_Event {
			folders_visited = session.folders_count,
			repos_found     = intrinsics.atomic_load(&session.found_count),
			repos_inspected = intrinsics.atomic_load(&session.inspected),
			repos_queued    = inspect_outstanding(session),
		},
	})
}

Inspect_Task :: struct {
	session:   ^Scan_Session,
	root_path: string,
}

inspect_task :: proc(task: thread.Task) {
	data := cast(^Inspect_Task)task.data
	defer {
		delete(data.root_path, task.allocator)
		free(task.data, task.allocator)
	}

	if is_cancelled(data.session) do return

	repo := git.inspect_repository(data.root_path, data.session.scan_root, task.allocator)
	intrinsics.atomic_add(&data.session.inspected, 1)

	emit(data.session, Scan_Event {
		kind = .Repo_Inspected,
		data = Repo_Inspected_Event{repository = repo},
	})
	emit_progress(data.session)
}

ensure_pool :: proc(session: ^Scan_Session) {
	if session.pool_ready do return
	thread.pool_init(&session.pool, session.allocator, MAX_GIT_WORKERS)
	thread.pool_start(&session.pool)
	session.pool_ready = true
}

// Block the scanner until git inspect backlog drops below the cap.
wait_for_inspect_capacity :: proc(session: ^Scan_Session) {
	for {
		if is_cancelled(session) do return
		if !session.pool_ready do return
		if inspect_outstanding(session) < MAX_INSPECT_OUTSTANDING do return
		thread.yield()
		time.sleep(5 * time.Millisecond)
	}
}

enqueue_inspect :: proc(session: ^Scan_Session, root_path: string) {
	if is_cancelled(session) do return

	wait_for_inspect_capacity(session)
	if is_cancelled(session) do return

	ensure_pool(session)

	task_data := new(Inspect_Task, session.allocator)
	task_data.session = session
	task_data.root_path = strings.clone(root_path, session.allocator) or_else root_path

	thread.pool_add_task(
		&session.pool,
		session.allocator,
		inspect_task,
		task_data,
	)
}

on_repo_found :: proc(path: string, user_data: rawptr) {
	session := cast(^Scan_Session)user_data

	rel := "."
	if r, err := os.get_relative_path(session.scan_root, path, context.temp_allocator); err == nil {
		rel = r
	}

	intrinsics.atomic_add(&session.found_count, 1)

	emit(session, Scan_Event {
		kind = .Repo_Discovered,
		data = Repo_Discovered_Event {
			root_path     = strings.clone(path, session.allocator) or_else path,
			relative_path = strings.clone(rel, session.allocator) or_else rel,
		},
	})

	enqueue_inspect(session, path)
	emit_progress(session)
}

on_walk_progress :: proc(folders_visited: int, user_data: rawptr) {
	session := cast(^Scan_Session)user_data
	session.folders_count = folders_visited
	emit_progress(session)
}

scanner_thread_main :: proc(session: ^Scan_Session) {
	ctx := scanner.Scan_Context {
		seen_roots        = session.seen_roots,
		folders_visited   = &session.folders_count,
		cancelled         = &session.cancelled,
		scan_nested_repos = session.scan_nested_repos,
		on_repo           = on_repo_found,
		on_progress       = on_walk_progress,
		user_data         = session,
	}

	scanner.scan_root(&ctx, session.scan_root, session.allocator)

	if session.pool_ready {
		thread.pool_finish(&session.pool)
	}

	emit(session, Scan_Event {
		kind = .Scan_Complete,
		data = Scan_Complete_Event{},
	})
}

start_scan :: proc(session: ^Scan_Session, scan_root: string, scan_nested: bool) {
	reset(session, scan_root, scan_nested)
	emit_progress(session)
	thread.run_with_data(session, proc(data: rawptr) {
		scanner_thread_main(cast(^Scan_Session)data)
	}, context)
}

poll_event :: proc(session: ^Scan_Session) -> (Scan_Event, bool) {
	return chan.try_recv(session.event_chan)
}

drain_events :: proc(session: ^Scan_Session, handler: proc(_: ^Scan_Session, _: Scan_Event, _: rawptr), user_data: rawptr, max_events := MAX_EVENTS_PER_FRAME) {
	for _ in 0 ..< max_events {
		event, ok := poll_event(session)
		if !ok do break
		handler(session, event, user_data)
	}
}
