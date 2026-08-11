package ui

import "core:strings"
import rl "vendor:raylib"

Button_Result :: struct {
	pressed: bool,
	hover:   bool,
}

draw_rect :: proc(x, y, w, h: i32, col: rl.Color) {
	rl.DrawRectangle(x, y, w, h, col)
}

draw_text :: proc(text: string, x, y: i32, size: f32, col: rl.Color) {
	draw_text_ex(text, x, y, size, col)
}

measure_text :: proc(text: string, size: f32) -> i32 {
	return measure_text_ex(text, size)
}

point_in_rect :: proc(px, py, x, y, w, h: i32) -> bool {
	return px >= x && px < x + w && py >= y && py < y + h
}

TOOLTIP_PAD :: 8
TOOLTIP_GAP :: 8

draw_tooltip :: proc(text: string, mx, my: i32) {
	tw := measure_text(text, FONT_SMALL)
	th := i32(FONT_SMALL)
	pad := i32(TOOLTIP_PAD)
	box_w := tw + pad * 2
	box_h := th + pad * 2

	tx := mx + TOOLTIP_GAP
	ty := my + TOOLTIP_GAP

	sw := rl.GetScreenWidth()
	sh := rl.GetScreenHeight()
	if tx + box_w > sw {
		tx = mx - box_w - TOOLTIP_GAP
	}
	if ty + box_h > sh {
		ty = my - box_h - TOOLTIP_GAP
	}
	tx = max(0, tx)
	ty = max(0, ty)

	draw_rect(tx, ty, box_w, box_h, COL_PANEL2)
	rl.DrawRectangleLines(tx, ty, box_w, box_h, COL_BORDER)
	draw_text(text, tx + pad, ty + pad, FONT_SMALL, COL_TEXT)
}

button :: proc(label: string, x, y, w, h: i32, enabled := true) -> Button_Result {
	res: Button_Result
	mx := rl.GetMouseX()
	my := rl.GetMouseY()
	res.hover = enabled && point_in_rect(mx, my, x, y, w, h)

	bg := COL_PANEL2
	if !enabled {
		bg = COL_PANEL
	} else if res.hover {
		bg = COL_BORDER
	}

	draw_rect(x, y, w, h, bg)
	rl.DrawRectangleLines(x, y, w, h, COL_BORDER)

	tw := measure_text(label, FONT_BODY)
	th := i32(FONT_BODY)
	draw_text(label, x + (w - tw) / 2, y + (h - th) / 2, FONT_BODY, enabled ? COL_TEXT : COL_MUTED)

	if enabled && res.hover && rl.IsMouseButtonPressed(.LEFT) {
		res.pressed = true
	}
	return res
}

text_input :: proc(
	buffer: ^[512]u8,
	length: ^int,
	x, y, w, h: i32,
	placeholder: string,
) {
	draw_rect(x, y, w, h, COL_PANEL)
	rl.DrawRectangleLines(x, y, w, h, COL_BORDER)

	text := string(buffer[:length^])
	display := text
	if len(display) == 0 do display = placeholder
	col := COL_TEXT if len(text) > 0 else COL_MUTED
	th := i32(FONT_BODY)
	draw_text(display, x + 8, y + (h - th) / 2, FONT_BODY, col)

	for ch := rl.GetCharPressed(); ch > 0; ch = rl.GetCharPressed() {
		if length^ < len(buffer) - 1 && ch >= 32 && ch < 127 {
			buffer[length^] = u8(ch)
			length^ += 1
		}
	}

	if rl.IsKeyPressed(.BACKSPACE) && length^ > 0 {
		length^ -= 1
	}
}
