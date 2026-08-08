package ui

import "core:os"
import filepath "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

// Rasterize the atlas at this pixel height; draw sizes should stay at or below this.
FONT_ATLAS_PX :: 72

FONT_TITLE   :: f32(28)
FONT_HEADING :: f32(20)
FONT_BODY    :: f32(17)
FONT_SMALL   :: f32(14)
FONT_SPACING :: f32(1)

BUNDLED_FONT_NAMES :: []string{"ui.ttf", "font.ttf", "Inter-Regular.ttf", "JetBrainsMono-Regular.ttf"}

Font_State :: struct {
	font:             rl.Font,
	loaded:           bool,
	uses_custom_font: bool,
}

font_state: Font_State

when ODIN_OS == .Windows {
	SYSTEM_FONT_CANDIDATES := []string{
		`C:\Windows\Fonts\segoeui.ttf`,
		`C:\Windows\Fonts\segoeuil.ttf`,
		`C:\Windows\Fonts\calibri.ttf`,
		`C:\Windows\Fonts\arial.ttf`,
	}
} else when ODIN_OS == .Darwin {
	SYSTEM_FONT_CANDIDATES := []string{
		"/System/Library/Fonts/SFNSText.ttf",
		"/System/Library/Fonts/Supplemental/Arial.ttf",
		"/Library/Fonts/Arial.ttf",
	}
} else {
	SYSTEM_FONT_CANDIDATES := []string{
		"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
		"/usr/share/fonts/TTF/DejaVuSans.ttf",
		"/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
		"/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf",
	}
}

init_font :: proc() {
	for path in font_search_paths() {
		if try_load_font(path) do return
	}
	font_state.font = rl.GetFontDefault()
	font_state.loaded = true
	font_state.uses_custom_font = false
}

unload_font :: proc() {
	if !font_state.loaded do return
	if font_state.uses_custom_font {
		rl.UnloadFont(font_state.font)
	}
	font_state.loaded = false
	font_state.uses_custom_font = false
}

font :: proc() -> rl.Font {
	if !font_state.loaded {
		init_font()
	}
	return font_state.font
}

draw_text_ex :: proc(text: string, x, y: i32, size: f32, col: rl.Color) {
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	rl.DrawTextEx(font(), cstr, {f32(x), f32(y)}, size, FONT_SPACING, col)
}

measure_text_ex :: proc(text: string, size: f32) -> i32 {
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	v := rl.MeasureTextEx(font(), cstr, size, FONT_SPACING)
	return i32(v.x + 0.5)
}

@(private)
try_load_font :: proc(path: string) -> bool {
	if !os.exists(path) do return false
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	f := rl.LoadFontEx(cpath, FONT_ATLAS_PX, nil, 0)
	if !rl.IsFontValid(f) do return false
	rl.SetTextureFilter(f.texture, .BILINEAR)
	font_state.font = f
	font_state.loaded = true
	font_state.uses_custom_font = true
	return true
}

@(private)
font_search_paths :: proc() -> []string {
	paths := make([dynamic]string, context.temp_allocator)

	// Drop your font at assets/fonts/ui.ttf (next to the exe or cwd).
	for base in bundled_font_bases() {
		for name in BUNDLED_FONT_NAMES {
			if p, err := filepath.join({base, "assets", "fonts", name}); err == nil {
				append(&paths, p)
			}
		}
	}

	for sys in SYSTEM_FONT_CANDIDATES {
		append(&paths, sys)
	}

	return paths[:]
}

@(private)
bundled_font_bases :: proc() -> []string {
	bases := make([dynamic]string, context.temp_allocator)
	append(&bases, os.get_working_directory(context.temp_allocator) or_else ".")

	if exe_dir, err := os.get_executable_directory(context.temp_allocator); err == nil {
		append(&bases, exe_dir)
	}

	return bases[:]
}
