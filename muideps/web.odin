//+build js
package muideps

import mu "vendor:microui"
import js "vendor:wasm/js"
import    "core:strings"
import    "core:unicode"
import    "core:fmt"
import    "core:runtime"
import    "core:intrinsics"

foreign import cv "canvas" 

@(default_calling_convention="contextless")
foreign cv {
    js_save_file             :: proc(filename: string, content: string) ---
    js_open_file_dialogue    :: proc(callback: proc "odin" ()) ---

    get_return_string_length :: proc() -> uintptr ---
    get_return_string        :: proc(b: []byte) -> uintptr ---

    load_event_string_buffer :: proc(b: []byte) ---
    print_something          :: proc(s: string) ---
    set_loop_target          :: proc(t: proc "odin" ()) ---
    js_text_width            :: proc(s: string) -> f64 ---
    js_text_height           :: proc() -> f64 ---
    js_get_width             :: proc() -> f64 ---
    js_get_height            :: proc() -> f64 ---

    fill_canvas :: proc(color: string) ---
    fill_rect :: proc(x, y, w, h: f64, color: string) ---
    draw_text :: proc(x, y: f64, s: string, color: string) ---
}

jsCallContext: runtime.Context
@(export)
call_fn :: proc(fn: proc()) {
    context = jsCallContext
    fn()
}

eventStringBuffer: []byte
@(export)
request_new_event_string_buffer :: proc() {
    load_event_string_buffer(eventStringBuffer)
}

// putting this here means I don't have to pass it everywhere js side
smctx: ^mu.Context = {}

init :: proc() -> ^mu.Context {
    jsCallContext = context

    mctx, err := new(mu.Context)
    fmt.println(size_of(mu.Context), err)
    mu.init(mctx)
    mctx.text_width = text_width
    mctx.text_height = text_height
    smctx = mctx

    eventStringBuffer = make([]byte, 512)
    
    js.add_event_listener("drawCanvas", js.Event_Kind.Pointer_Down, nil, proc(e: js.Event) {
        mu.input_mouse_down(smctx, i32(e.data.mouse.offset.x), i32(e.data.mouse.offset.y), mu.Mouse(e.data.mouse.button))
    })
    js.add_event_listener("drawCanvas", js.Event_Kind.Pointer_Up, nil, proc(e: js.Event) {
        mu.input_mouse_up(smctx, i32(e.data.mouse.offset.x), i32(e.data.mouse.offset.y), mu.Mouse(e.data.mouse.button))
    })
    js.add_event_listener("drawCanvas", .Mouse_Move, nil, proc(e: js.Event) {
        mu.input_mouse_move(smctx, i32(e.data.mouse.offset.x), i32(e.data.mouse.offset.y))
    })
    js.add_window_event_listener(js.Event_Kind.Key_Down, nil, proc(e: js.Event) {
        switch {
            case e.data.key.key == "Control"  : mu.input_key_down(smctx, mu.Key.CTRL     )
            case e.data.key.key == "Shift"    : mu.input_key_down(smctx, mu.Key.SHIFT    )
            case e.data.key.key == "Alt"      : mu.input_key_down(smctx, mu.Key.ALT      )
            case e.data.key.key == "Enter"    : mu.input_key_down(smctx, mu.Key.RETURN   )
            case e.data.key.key == "Backspace": mu.input_key_down(smctx, mu.Key.BACKSPACE)
            case: mu.input_text(smctx, e.data.key.key)
        }
    })
    js.add_window_event_listener(js.Event_Kind.Wheel, nil, proc(e: js.Event) {
        mu.input_scroll(smctx, i32(e.data.wheel.delta.x), i32(e.data.wheel.delta.y))
        fmt.println(e, e.data.wheel)
    })
    

    return mctx
}

loop :: proc(frame: proc(^mu.Context), mctx: ^mu.Context) {
    @(static) sframe: proc(^mu.Context) = {}
    sframe = frame // too lazy to pass this through JS

    set_loop_target(proc() {sframe(smctx)})
}

text_width :: proc(f: mu.Font, s: string) -> i32 {
    return cast(i32)js_text_width(s)
}

text_height :: proc(f: mu.Font) -> i32 {
    return cast(i32)js_text_height()
}

get_width  :: proc() -> i32 {return cast(i32)js_get_width()}
get_height :: proc() -> i32 {return cast(i32)js_get_height()}

get_input :: proc(mctx: ^mu.Context) {
    // input handled via callbacks instead of querying frame-by-frame
}

input_callback :: proc(e: js.Event) {
}


draw :: proc(mctx: ^mu.Context) {
    fill_canvas("#000000ff")

    mcmd: ^mu.Command
    colorBuf := [9]byte{}
    for mu.next_command(mctx, &mcmd) {
        #partial switch cmd in mcmd.variant {
            case ^mu.Command_Rect: fill_rect(f64(cmd.rect.x), f64(cmd.rect.y), f64(cmd.rect.w), f64(cmd.rect.h), color_for_canvas(cmd.color, &colorBuf))
            case ^mu.Command_Text: draw_text(f64(cmd.pos.x ), f64(cmd.pos.y ), cmd.str, color_for_canvas(cmd.color, &colorBuf))
        }
    }
}

color_for_canvas :: proc(color: mu.Color, buf: ^[9]byte) -> string {
    return fmt.bprintf(buf[:], "#%2x%2x%2x%2x", color.r, color.g, color.b, color.a)
}

save_file :: js_save_file

fileReady := false
open_file_dialogue :: proc() -> (ingame: bool) {
    js_open_file_dialogue(proc() {
        fileReady = true
    })

    return false
}

in_game_file_dialogue :: proc(mctx: ^mu.Context) {}

get_selected_file_data :: proc() -> []byte {
    if !fileReady do return nil

    strLen := get_return_string_length()
    ret := make([]byte, strLen)
    get_return_string(ret)

    fileReady = false
    return ret
}
