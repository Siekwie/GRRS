package platform

choose_folder :: proc() -> (path: string, ok: bool) {
	when ODIN_OS == .Windows {
		return choose_folder_windows()
	}
	return "", false
}
