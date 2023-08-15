//+build !js
package muideps

import rl "vendor:raylib"
import mu "vendor:microui"
import    "core:strings"
import    "core:unicode"
import    "core:os"

init :: proc() -> ^mu.Context {
    rl.InitWindow(800, 600, "microUI test")
    rl.SetTargetFPS(60)

    mctx, err := new(mu.Context)
    mu.init(mctx)
    mctx.text_width = text_width
    mctx.text_height = text_height

    return mctx
}

loop :: proc(frame: proc(^mu.Context), mctx: ^mu.Context) {
    for !rl.WindowShouldClose() {
        frame(mctx)
    }
}

TEXT_SIZE :: 10

text_width :: proc(f: mu.Font, s: string) -> i32 {
    cs := strings.clone_to_cstring(s)
    defer delete(cs)
    return rl.MeasureText(cs, TEXT_SIZE) + 1
}

text_height :: proc(f: mu.Font) -> i32 {return TEXT_SIZE}

get_width  :: proc() -> i32 {return cast(i32)rl.GetScreenWidth()}
get_height :: proc() -> i32 {return cast(i32)rl.GetScreenHeight()}

get_input :: proc(mctx: ^mu.Context) {
    mouseMove := rl.GetMouseDelta()

    mu.input_mouse_move(mctx, rl.GetMouseX(), rl.GetMouseY())
    for mb in rl.MouseButton {
        if rl.IsMouseButtonPressed(mb) {
            mu.input_mouse_down(mctx, rl.GetMouseX(), rl.GetMouseY(), mu.Mouse(mb))
        }
        if rl.IsMouseButtonReleased(mb) {
            mu.input_mouse_up(mctx, rl.GetMouseX(), rl.GetMouseY(), mu.Mouse(mb))
        }
    }

    {
        sb := strings.builder_make()
        defer strings.builder_destroy(&sb)

        for {
            next := rune(rl.GetKeyPressed())
            if next == 0 do break

            if unicode.is_print(next) {
                if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) || rl.IsKeyDown(rl.KeyboardKey.RIGHT_SHIFT) {
                    next = unicode.to_upper(next)
                } else {
                    next = unicode.to_lower(next)
                }
            } else do continue

            strings.write_rune(&sb, next)
        }

        mu.input_text(mctx, strings.to_string(sb))
    }

    for kp in rl.KeyboardKey {
        rl_to_mu_key :: proc(k: rl.KeyboardKey) -> Maybe(mu.Key) {
            #partial switch k {
                case .LEFT_SHIFT, .RIGHT_SHIFT: return .SHIFT
                case .LEFT_CONTROL, .RIGHT_CONTROL: return .CTRL
                case .LEFT_ALT, .RIGHT_ALT: return .ALT
                case .ENTER, .KP_ENTER: return .RETURN
                case .BACKSPACE: return .BACKSPACE
            }
            return nil
        }
        mkp := rl_to_mu_key(kp)
        if mkp == nil do continue


        if rl.IsKeyPressed(kp) {
            mu.input_key_down(mctx, mkp.(mu.Key))
        }
        if rl.IsKeyReleased(kp) {
            mu.input_key_up(mctx, mkp.(mu.Key))
        }
    }
}


draw :: proc(mctx: ^mu.Context) {
    rl.BeginDrawing()
    defer rl.EndDrawing()
    rl.ClearBackground(rl.BLACK)

    mcmd: ^mu.Command
    for mu.next_command(mctx, &mcmd) {
        #partial switch cmd in mcmd.variant {
            case ^mu.Command_Rect: rl.DrawRectangle(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h, cast(rl.Color)cmd.color)
            case ^mu.Command_Text: 
                cs := strings.clone_to_cstring(cmd.str)
                defer delete(cs)
                rl.DrawText(cs, cmd.pos.x, cmd.pos.y, TEXT_SIZE, cast(rl.Color)cmd.color)
        }
    }
}

SAVE_DIR :: "saves"

save_file :: proc(filename: string, content: string) {
    file := strings.concatenate({SAVE_DIR, "/", filename})
    defer delete(file)
    
    os.write_entire_file(file, transmute([]byte)content)
}

saveFiles: []os.File_Info
saveFileData: []byte
open_file_dialogue :: proc() -> (ingame: bool) {
    if !os.is_dir_path(SAVE_DIR) do os.make_directory(SAVE_DIR)

    handle, hOk := os.open(SAVE_DIR)
    defer os.close(handle)

    if saveFiles != nil do os.file_info_slice_delete(saveFiles)

    dirErr: os.Errno
    saveFiles, dirErr = os.read_dir(handle, 0)

    return true
}

in_game_file_dialogue :: proc(mctx: ^mu.Context) {
    if saveFiles == nil do return

    mu.layout_row(mctx, {-25, -1}, 0)

    for saveFile in saveFiles {
        mu.push_id(mctx, saveFile.name)
        defer mu.pop_id(mctx)

        mu.text(mctx, saveFile.name)
        if .SUBMIT in mu.button(mctx, ">") {
            ok: bool
            saveFileData, ok = os.read_entire_file(saveFile.fullpath)
        }
    }

    mu.layout_row(mctx, {}, 0)
}

get_selected_file_data :: proc() -> []byte {
    if saveFileData == nil do return nil
    defer saveFileData = nil

    return saveFileData
}
