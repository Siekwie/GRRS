package git

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

GIT_EXE :: "git"

Command_Result :: struct {
	stdout:        string,
	stderr:        string,
	exit_code:     int,
	ok:            bool,
	error_message: string,
}

run :: proc(repo_path: string, args: []string, allocator := context.allocator) -> Command_Result {
	result: Command_Result

	cmd := make([dynamic]string, 0, 3 + len(args), context.temp_allocator)
	append(&cmd, GIT_EXE)
	append(&cmd, "-C")
	append(&cmd, repo_path)
	for arg in args {
		append(&cmd, arg)
	}

	desc := os.Process_Desc {
		command = cmd[:],
	}

	state, stdout_bytes, stderr_bytes, err := os.process_exec(desc, allocator)
	if err != nil {
		result.error_message = fmt.tprintf("process error: %v", err)
		return result
	}

	result.stdout = string(stdout_bytes)
	result.stderr = string(stderr_bytes)
	result.exit_code = state.exit_code
	result.ok = state.success && state.exit_code == 0
	if !result.ok && len(result.stderr) == 0 && len(result.stdout) > 0 {
		result.stderr = result.stdout
	}
	return result
}

run_plain :: proc(args: []string, allocator := context.allocator) -> Command_Result {
	result: Command_Result

	cmd := make([dynamic]string, 0, 1 + len(args), context.temp_allocator)
	append(&cmd, GIT_EXE)
	for arg in args {
		append(&cmd, arg)
	}

	desc := os.Process_Desc {
		command = cmd[:],
	}

	state, stdout_bytes, stderr_bytes, err := os.process_exec(desc, allocator)
	if err != nil {
		result.error_message = fmt.tprintf("process error: %v", err)
		return result
	}

	result.stdout = string(stdout_bytes)
	result.stderr = string(stderr_bytes)
	result.exit_code = state.exit_code
	result.ok = state.success && state.exit_code == 0
	return result
}

available :: proc() -> bool {
	res := run_plain({"--version"}, context.temp_allocator)
	return res.ok
}

verify_repo_root :: proc(path: string, allocator := context.allocator) -> (root: string, ok: bool) {
	res := run(path, {"rev-parse", "--show-toplevel"}, allocator)
	if !res.ok do return "", false
	root = strings.trim_right(strings.trim_left(res.stdout, "\r\n"), "\r\n")
	return root, len(root) > 0
}

count_local_branches :: proc(repo_path: string, allocator := context.allocator) -> int {
	res := run(repo_path, {"for-each-ref", "--format=%(refname:short)", "refs/heads"}, allocator)
	if !res.ok do return 0
	count := 0
	for line in strings.split_lines(res.stdout, context.temp_allocator) {
		if len(strings.trim_space(line)) > 0 {
			count += 1
		}
	}
	return count
}

query_upstream_divergence :: proc(repo_path: string, allocator := context.allocator) -> (
	upstream: string,
	ahead: int,
	behind: int,
	ok: bool,
) {
	up_res := run(repo_path, {"rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"}, allocator)
	if !up_res.ok {
		return "", 0, 0, false
	}
	upstream = strings.trim_right(strings.trim_left(up_res.stdout, "\r\n"), "\r\n")

	div_res := run(repo_path, {"rev-list", "--left-right", "--count", "@{upstream}...HEAD"}, allocator)
	if !div_res.ok {
		return upstream, 0, 0, true
	}
	parts := strings.fields(strings.trim_space(div_res.stdout), context.temp_allocator)
	if len(parts) >= 2 {
		behind = parse_int(parts[0])
		ahead = parse_int(parts[1])
	}
	return upstream, ahead, behind, true
}

now_unix :: proc() -> i64 {
	return time.to_unix_seconds(time.now())
}

@(private)
parse_int :: proc(s: string) -> int {
	n := 0
	for c in s {
		if c >= '0' && c <= '9' {
			n = n * 10 + int(c - '0')
		}
	}
	return n
}
