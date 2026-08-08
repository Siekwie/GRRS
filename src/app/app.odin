package app

import "core:fmt"

import "src:git"
import "src:jobs"
import "src:model"
import "src:ui"
import rl "vendor:raylib"

run :: proc() {
	if !git.available() {
		fmt.eprintln("Git is not available on PATH. Install Git and try again.")
		return
	}

	state: model.App_State
	model.init_state(&state)
	defer model.destroy_state(&state)

	session := jobs.create_session()
	defer jobs.destroy_session(&session)

	ui.open_window()
	defer ui.close_window()

	for !ui.should_close() {
		free_all(context.temp_allocator)

		// Process scan events before drawing so progress stays responsive.
		jobs.drain_events(&session, drain_handler, &state)

		if state.is_scanning {
			state.scan_anim += f32(rl.GetFrameTime()) * 4
		}

		ui.begin_frame()

		switch state.screen {
		case .Folder_Select:
			picker := ui.draw_folder_picker(&state)
			if picker.should_open && validate_scan_root(picker.submitted_path) {
				begin_scan(&state, &session, picker.submitted_path)
			}
		case .Scan_Results:
			table := ui.draw_repo_table(&state)
			switch table.action {
			case ui.Repo_Table_Action.None:
			case ui.Repo_Table_Action.Rescan:
				if len(state.scan_root) > 0 {
					begin_scan(&state, &session, state.scan_root)
				}
			case ui.Repo_Table_Action.Change_Root:
				if state.is_scanning {
					cancel_scan(&state, &session)
				}
				state.screen = .Folder_Select
				set_path_input(&state, state.scan_root)
			case ui.Repo_Table_Action.Cancel_Scan:
				cancel_scan(&state, &session)
			}
		}

		ui.end_frame()
	}

	fmt.println("Git Repository Scanner closed.")
}

@(private)
drain_handler :: proc(session: ^jobs.Scan_Session, event: jobs.Scan_Event, user_data: rawptr) {
	state := cast(^model.App_State)user_data
	handle_scan_event(state, event)
}
