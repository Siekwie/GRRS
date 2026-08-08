package ui

import rl "vendor:raylib"

begin_frame :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(COL_BG)
}

end_frame :: proc() {
	rl.EndDrawing()
}

open_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(WINDOW_W, WINDOW_H, "Git Repository Scanner")
	rl.SetTargetFPS(60)
	init_font()
}

close_window :: proc() {
	unload_font()
	rl.CloseWindow()
}

should_close :: proc() -> bool {
	return rl.WindowShouldClose() || rl.IsKeyPressed(.ESCAPE)
}
