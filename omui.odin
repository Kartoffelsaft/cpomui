package omui

import mu "vendor:microui"
import    "core:strings"
import    "core:unicode"
import    "core:fmt"
import    "core:math"
import js "vendor:wasm/js"
import    "core:mem"
import    "core:slice"
import    "core:os"

import md "muideps"
import ja "jswrapalloc"

begin_static_window :: proc(ctx: ^mu.Context, title: string, rect: mu.Rect, opt: mu.Options) -> bool {
    if cnt := mu.get_container(ctx, title); cnt != nil do cnt.rect = rect
    return mu.begin_window(ctx, title, rect, opt)
}

CurrentMenu :: enum {
    MAIN,
    SAVES,
}
currentMenu := CurrentMenu.MAIN

left_window :: proc(mctx: ^mu.Context) {
    mu.layout_row(mctx, {-1}, 40)
    mu.layout_next(mctx)
    mu.layout_row(mctx, {-1}, 0)
    mu.get_current_container(mctx).scroll.y -= 10

    if .SUBMIT in mu.button(mctx, "Main") {
        currentMenu = .MAIN
    }

    if .SUBMIT in mu.button(mctx, "Saves") {
        currentMenu = .SAVES
    }
}

right_window :: proc(mctx: ^mu.Context) {
}

main_window :: proc(mctx: ^mu.Context) {
    switch currentMenu {
    case .MAIN:
        mu.layout_row(mctx, {-1}, 0)

        if mu.Result.SUBMIT in mu.button(mctx, "Button?") {
            fmt.println("Button!")
        }

        mu.text(mctx, `Consequatur rem animi totam enim aperiam laboriosam eum. Maxime rem quo incidunt numquam rerum et quos. Sunt debitis suscipit rerum ullam libero eveniet. Consequatur rem animi totam enim aperiam laboriosam eum. Maxime rem quo incidunt numquam rerum et quos. Sunt debitis suscipit rerum ullam libero eveniet. Consequatur rem animi totam enim aperiam laboriosam eum. Maxime rem quo incidunt numquam rerum et quos. Sunt debitis suscipit rerum ullam libero eveniet. `)

        @(static) allText: [dynamic]string 
        if allText == nil do allText = make([dynamic]string)
        @(static) mytext := [1024]byte{}
        @(static) tbLen: int
        if mu.Result.SUBMIT in mu.textbox(mctx, mytext[:], &tbLen) {
            fmt.println(strings.string_from_ptr(&mytext[0], tbLen))
            append(&allText, strings.clone_from(mytext[:tbLen]))
            mytext = {}
            tbLen = 0
        }

        #reverse for s in allText {
            mu.text(mctx, s)
        }
    case .SAVES:
        mu.layout_row(mctx, {mu.get_clip_rect(mctx).w / 2, -1}, 0)

        @(static) mode: enum {
            SAVE,
            LOAD,
        } = .SAVE

        if .SUBMIT in mu.button(mctx, "Save") {
            mode = .SAVE
        }

        @(static) ingameFileDialogue := false
        if .SUBMIT in mu.button(mctx, "Load") {
            ingameFileDialogue = md.open_file_dialogue()
            mode = .LOAD
        }

        mu.layout_row(mctx, {-1}, 0)

        switch mode {
        case .SAVE:
            mu.layout_row(mctx, {-25, -1}, 0)
            @(static) saveFileName := [128]byte{}
            @(static) saveFileNameLen := 0
            if .SUBMIT in mu.textbox(mctx, saveFileName[:], &saveFileNameLen) || .SUBMIT in mu.button(mctx, "V") {
                md.save_file(transmute(string)saveFileName[:saveFileNameLen], "My save file")

                saveFileName = {}
                saveFileNameLen = 0
            }
        case .LOAD:
            if ingameFileDialogue do md.in_game_file_dialogue(mctx)
        }

        mu.layout_row(mctx, {-1}, 0)

        when ODIN_OS == .JS do mu.text(mctx, "Currently the web version uses downloads & file dialogues for your saves")

    }
}

frame :: proc(mctx: ^mu.Context) {
    md.get_input(mctx) 

    if fd := md.get_selected_file_data(); fd != nil {
        fmt.println(transmute(string)fd)
        delete(fd)
    }

    {
        mu.begin(mctx)
        defer mu.end(mctx)

        begin_static_window(mctx, "Left Window", {0, 0, md.get_width()/4, md.get_height()}, {mu.Opt.NO_TITLE, mu.Opt.NO_CLOSE, mu.Opt.NO_RESIZE})
        left_window(mctx)
        mu.end_window(mctx)

        begin_static_window(mctx, "Main Window", {md.get_width()/4, 0, md.get_width()/2, md.get_height()}, {mu.Opt.NO_TITLE, mu.Opt.NO_CLOSE, mu.Opt.NO_RESIZE})
        main_window(mctx)
        mu.end_window(mctx)

        begin_static_window(mctx, "Right Window", {3*md.get_width()/4, 0, md.get_width()/4, md.get_height()}, {mu.Opt.NO_TITLE, mu.Opt.NO_CLOSE, mu.Opt.NO_RESIZE})
        right_window(mctx)
        mu.end_window(mctx)
    }

    md.draw(mctx)
}

main :: proc() {
    when ODIN_OS == .JS {
        jsAlloc := js.page_allocator()
        @(static) odAllocInfo := mem.Arena{}
        @(static) odAllocInfoData := [64 * mem.Kilobyte]byte{}
        mem.arena_init(&odAllocInfo, odAllocInfoData[:])

        // @(static) odAlloc := mem.Dynamic_Pool{}
        // mem.dynamic_pool_init(&odAlloc, jsAlloc, mem.arena_allocator(&odAllocInfo), js.PAGE_SIZE * 32)
        // context.allocator = mem.dynamic_pool_allocator(&odAlloc)

        @(static) odAlloc := ja.JsWrapAlloc{}
        ja.js_wrap_alloc_init(&odAlloc, jsAlloc, mem.arena_allocator(&odAllocInfo))
        context.allocator = ja.js_wrap_allocator(&odAlloc)
    }

    mctx := md.init()
    defer free(mctx)

    md.loop(frame, mctx)

}
