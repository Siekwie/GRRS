package scanner

// Directories we never enter during a filesystem walk.
SKIP_DIR_NAMES :: []string {
	".git",
	"node_modules",
	"target",
	"build",
	"dist",
	"out",
	".venv",
	"venv",
	"__pycache__",
	".gradle",
	".cargo",
	".npm",
	".yarn",
	".pnpm-store",
	".idea",
	".vs",
	"packages", // nuget cache-style trees inside large monorepos
}

should_skip_dir :: proc(name: string) -> bool {
	for skip in SKIP_DIR_NAMES {
		if name == skip do return true
	}
	return false
}
