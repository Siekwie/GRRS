package scanner

import "core:fmt"
import "core:os"
import "core:strings"

import "src:git"

PROGRESS_INTERVAL :: 25

Scan_Callback :: proc(path: string, user_data: rawptr)
Progress_Callback :: proc(folders_visited: int, user_data: rawptr)

Scan_Context :: struct {
	scan_root:         string,
	seen_roots:        map[string]bool,
	folders_visited:   ^int,
	cancelled:         ^bool,
	scan_nested_repos: bool,
	on_repo:           Scan_Callback,
	on_progress:       Progress_Callback,
	user_data:         rawptr,
	warnings:          ^[dynamic]string,
}

scan_root :: proc(ctx: ^Scan_Context, root: string, allocator := context.allocator) {
	ctx.scan_root = strings.clone(root, allocator) or_else root
	defer delete(ctx.scan_root)

	stack := make([dynamic]string, allocator)
	defer {
		for p in stack do delete(p)
		delete(stack)
	}
	append(&stack, ctx.scan_root)

	for len(stack) > 0 {
		if ctx.cancelled != nil && ctx.cancelled^ {
			break
		}

		dir := stack[len(stack) - 1]
		ordered_remove(&stack, len(stack) - 1)

		if ctx.folders_visited != nil {
			ctx.folders_visited^ += 1
			if ctx.on_progress != nil && ctx.folders_visited^ % PROGRESS_INTERVAL == 0 {
				ctx.on_progress(ctx.folders_visited^, ctx.user_data)
			}
		}

		entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		if err != nil {
			if ctx.warnings != nil {
				append(ctx.warnings, fmt.tprintf("%v: %v", dir, err))
			}
			continue
		}

		is_repo := false
		for entry in entries {
			if entry.name == ".git" {
				is_repo = true
				break
			}
		}

		if is_repo {
			if root_path, ok := git.verify_repo_root(dir, allocator); ok {
				abs, abs_err := os.get_absolute_path(root_path, allocator)
				key := root_path
				if abs_err == nil {
					key = abs
				}
				if !ctx.seen_roots[key] {
					ctx.seen_roots[key] = true
					if ctx.on_repo != nil {
						ctx.on_repo(root_path, ctx.user_data)
					}
				}
				// Do not walk inside a verified repository unless nested scan is enabled.
				if !ctx.scan_nested_repos {
					continue
				}
			}
		}

		for entry in entries {
			if entry.name == ".git" do continue
			if entry.type != .Directory && entry.type != .Symlink do continue
			if should_skip_dir(entry.name) do continue

			child := ""
			child, _ = os.join_path({dir, entry.name}, allocator)
			append(&stack, child)
		}
	}

	if ctx.on_progress != nil && ctx.folders_visited != nil {
		ctx.on_progress(ctx.folders_visited^, ctx.user_data)
	}
}
