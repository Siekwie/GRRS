package ui

import "core:os"
import "core:strings"
import rl "vendor:raylib"

import "src:model"
import "src:platform"

Folder_Picker_Result :: struct {
	submitted_path: string,
	should_open:    bool,
}

draw_folder_picker :: proc(state: ^model.App_State) -> Folder_Picker_Result {
	result: Folder_Picker_Result

	w := rl.GetScreenWidth()
	h := rl.GetScreenHeight()

	draw_text("Git Repository Scanner", w / 2 - measure_text("Git Repository Scanner", FONT_TITLE) / 2, h / 3 - 60, FONT_TITLE, COL_TEXT)

	btn_w: i32 = 220
	btn_h: i32 = 36
	btn_x := w / 2 - btn_w / 2
	btn_y := h / 3

	if button("Select scan folder", btn_x, btn_y, btn_w, btn_h).pressed {
		if path, ok := platform.choose_folder(); ok {
			result.submitted_path = strings.clone(path, context.allocator) or_else path
			result.should_open = true
		}
	}

	label_y := btn_y + btn_h + 36
	draw_text("Or paste a path:", PAD, label_y, FONT_BODY, COL_MUTED)

	input_y := label_y + 24
	input_w := w - PAD * 2 - 90
	text_input(&state.path_input, &state.path_input_len, PAD, input_y, input_w, 36, "C:\\path\\to\\projects")

	if button("Open", PAD + input_w + 8, input_y, 82, 36).pressed {
		path := strings.trim_space(string(state.path_input[:state.path_input_len]))
		if len(path) > 0 && os.is_directory(path) {
			result.submitted_path = strings.clone(path, context.allocator) or_else path
			result.should_open = true
		} else {
			delete(state.status_message)
			state.status_message = strings.clone("Path is missing or not a directory.", context.allocator) or_else ""
		}
	}

	if len(state.status_message) > 0 {
		draw_text(state.status_message, PAD, input_y + 48, FONT_SMALL, COL_BAD)
	}

	return result
}
