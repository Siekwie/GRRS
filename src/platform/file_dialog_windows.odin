package platform

import "core:strings"
import win32 "core:sys/windows"

choose_folder_windows :: proc() -> (path: string, ok: bool) {
	win32.CoInitializeEx(nil, win32.COINIT.APARTMENTTHREADED)
	defer win32.CoUninitialize()

	dialog: ^win32.IFileOpenDialog
	hr := win32.CoCreateInstance(
		win32.CLSID_FileOpenDialog,
		nil,
		win32.CLSCTX_INPROC_SERVER,
		win32.IID_IFileOpenDialog,
		(^rawptr)(&dialog),
	)
	if hr != win32.S_OK do return "", false
	defer com_release(dialog)

	fd := cast(^win32.IFileDialog)dialog
	options: win32.FILEOPENDIALOGOPTIONS
	if fd.Vtbl.GetOptions(fd, &options) != win32.S_OK do return "", false
	options |= win32.FOS_PICKFOLDERS | win32.FOS_FORCEFILESYSTEM
	if fd.Vtbl.SetOptions(fd, options) != win32.S_OK do return "", false

	if fd.Vtbl.Show(cast(^win32.IModalWindow)fd, nil) != win32.S_OK do return "", false

	item: ^win32.IShellItem
	if fd.Vtbl.GetResult(fd, &item) != win32.S_OK do return "", false
	defer com_release(item)

	name_w: win32.LPWSTR
	if item.Vtbl.GetDisplayName(item, win32.SIGDN.FILESYSPATH, &name_w) != win32.S_OK do return "", false
	defer win32.CoTaskMemFree(name_w)

	path, _ = win32.wstring_to_utf8(win32.wstring(name_w), -1, context.allocator)
	return path, len(path) > 0
}

@(private)
com_release :: proc(obj: rawptr) {
	if obj == nil do return
	unk := cast(^win32.IUnknown)obj
	unk._iunknown_vtable.Release(unk)
}
