//+build js
package jswrapalloc

import "core:mem"
import "vendor:wasm/js"
import "core:slice"
import "core:intrinsics"
import "core:fmt"

SMALL_PER_LARGE :: 64
LARGE_PAGE_SIZE :: js.PAGE_SIZE
SMALL_PAGE_SIZE :: LARGE_PAGE_SIZE / SMALL_PER_LARGE
SEARCH_THRESHOLD :: 16

JsWrapAlloc :: struct {
    usedBlocks: [dynamic]u64,
    firstPage: int,
}

js_wrap_alloc_init :: proc(data: ^JsWrapAlloc, backingAlloc: mem.Allocator, trackingAlloc := context.allocator) {
    data.usedBlocks = make([dynamic]u64, trackingAlloc)
    data.firstPage = intrinsics.wasm_memory_grow(0, 0)
}

block_usage_bits_r :: proc(pages: uint) -> u64 {return (1 << pages) - 1}
block_usage_bits_l :: proc(pages: uint) -> u64 {return ~block_usage_bits_r(SMALL_PER_LARGE - pages)}

js_alloc :: proc(data: ^JsWrapAlloc, size: int, alignment: int) -> ([]byte, mem.Allocator_Error) {
    if size == 0 do return nil, nil
    assert(SMALL_PAGE_SIZE % alignment == 0)

    smallPagesNeeded := uint((size - 1) / SMALL_PAGE_SIZE + 1)
    largePagesNeeded := uint((size - 1) / LARGE_PAGE_SIZE + 1)

    from_new_large_block :: proc(data: ^JsWrapAlloc, size: int, alignment: int) -> ([]byte, mem.Allocator_Error) {
        smallPagesNeeded := uint((size - 1) / SMALL_PAGE_SIZE + 1)
        smallPagesNeeded %= SMALL_PER_LARGE
        largePagesNeeded := uint((size - 1) / LARGE_PAGE_SIZE + 1)

        for i in 0..<(largePagesNeeded-1) do append_elem(&data.usedBlocks, block_usage_bits_r(SMALL_PER_LARGE))

        if smallPagesNeeded == 0 {
            append_elem(&data.usedBlocks, block_usage_bits_r(SMALL_PER_LARGE))
        } else {
            append_elem(&data.usedBlocks, block_usage_bits_l(smallPagesNeeded))
        }
        
        prev_page_count := intrinsics.wasm_memory_grow(0, uintptr(largePagesNeeded))
        if prev_page_count < 0 {
            return nil, .Out_Of_Memory
        }

        ptr := ([^]byte)(uintptr(prev_page_count) * js.PAGE_SIZE)
        return ptr[:size], nil
    }
    

    if smallPagesNeeded > SMALL_PER_LARGE {
        return from_new_large_block(data, size, alignment)
    }

    // if block_usage_bits_r(smallPagesNeeded) & data.usedBlocks[len(data.usedBlocks)-1] == 0 {
    //     i := 0
    //     s := block_usage_bits_l(smallPagesNeeded)

    //     for s > block_usage_bits_r(smallPagesNeeded) && s&data.usedBlocks[len(data.usedBlocks)-1] != 0 {
    //         i += 1
    //         s >>= 1
    //     }

    //     data.usedBlocks[len(data.usedBlocks)-1] |= s
    //     ptr := ([^]byte)(uintptr((len(data.usedBlocks)-1 + data.firstPage) * LARGE_PAGE_SIZE + (i * SMALL_PAGE_SIZE)))
    //     return ptr[:size], nil
    // }

    if smallPagesNeeded <= SEARCH_THRESHOLD {
        for j in 0..<len(data.usedBlocks) {
            if data.usedBlocks[j] == 0xffffffffffffffff do continue

            i := 0
            s := block_usage_bits_l(smallPagesNeeded)

            for s >= block_usage_bits_r(smallPagesNeeded) && s&data.usedBlocks[j] != 0 {
                i += 1
                s >>= 1
            }
            if s < block_usage_bits_r(smallPagesNeeded) do continue

            data.usedBlocks[j] |= s
            ptr := ([^]byte)(uintptr(((j + data.firstPage) * LARGE_PAGE_SIZE) + (i * SMALL_PAGE_SIZE)))
            return ptr[:size], nil
        }

        return from_new_large_block(data, size, alignment)
    }

    return from_new_large_block(data, size, alignment)
}

js_free :: proc(data: ^JsWrapAlloc, ptr: rawptr, size: int) {
    if size == 0 do return
    assert(uintptr(ptr) % SMALL_PAGE_SIZE == 0)

    ptrn := uintptr(ptr) - uintptr(data.firstPage * LARGE_PAGE_SIZE)
    ptrnt := uintptr(ptr) - uintptr(data.firstPage * LARGE_PAGE_SIZE) + uintptr(size)
    
    largePageIdx := uint(ptrn / LARGE_PAGE_SIZE)
    smallPageIdx := uint((ptrn - uintptr(largePageIdx * LARGE_PAGE_SIZE)) / SMALL_PAGE_SIZE)

    largePageTermIdx := uint((ptrnt - 1) / LARGE_PAGE_SIZE + 1)
    smallPageTermIdx := uint((ptrnt - uintptr((largePageTermIdx-1) * LARGE_PAGE_SIZE) - 1) / SMALL_PAGE_SIZE + 1)

    smallPageCount := uint((size - 1)/SMALL_PAGE_SIZE + 1)

    if smallPageIdx + smallPageCount <= SMALL_PER_LARGE {
        data.usedBlocks[largePageIdx] &= ~(block_usage_bits_l(smallPageCount) >> smallPageIdx)
    } else {
        largePageStartClear := largePageIdx
        if smallPageIdx != 0 {
            data.usedBlocks[largePageStartClear] &= ~block_usage_bits_r(SMALL_PER_LARGE - smallPageIdx)
            largePageStartClear += 1
        }

        for i in largePageStartClear..<(largePageTermIdx-1) {
            data.usedBlocks[i] = 0
        }

        data.usedBlocks[largePageTermIdx-1] &= ~block_usage_bits_l(smallPageTermIdx)
    }
}

js_resize :: proc(data: ^JsWrapAlloc, optr: rawptr, osize: int, nsize: int, alignment: int) -> ([]byte, mem.Allocator_Error) {
    if osize == 0 {
        if nsize == 0 do return nil, nil
        else do return js_alloc(data, nsize, alignment)
    } else if nsize == 0 {
        js_free(data, optr, osize)
        return nil, nil
    }

    assert(SMALL_PAGE_SIZE % alignment == 0)
    assert(uintptr(optr) % SMALL_PAGE_SIZE == 0)

    ptrn := uintptr (optr) - uintptr(data.firstPage * LARGE_PAGE_SIZE)
    optrn := uintptr(optr) - uintptr(data.firstPage * LARGE_PAGE_SIZE) + uintptr(osize)
    nptrn := uintptr(optr) - uintptr(data.firstPage * LARGE_PAGE_SIZE) + uintptr(nsize)
    
    largePageIdx := uint(ptrn / LARGE_PAGE_SIZE)
    smallPageIdx := uint((ptrn - uintptr(largePageIdx * LARGE_PAGE_SIZE)) / SMALL_PAGE_SIZE)

    largePageOldTermIdx := uint((optrn - 1) / LARGE_PAGE_SIZE + 1)
    smallPageOldTermIdx := uint((optrn - uintptr((largePageOldTermIdx-1) * LARGE_PAGE_SIZE) - 1) / SMALL_PAGE_SIZE + 1)

    largePageNewTermIdx := uint((nptrn - 1) / LARGE_PAGE_SIZE + 1)
    smallPageNewTermIdx := uint((nptrn - uintptr((largePageNewTermIdx-1) * LARGE_PAGE_SIZE) - 1) / SMALL_PAGE_SIZE + 1)

    oldSmallPageCount := uint((osize - 1)/SMALL_PAGE_SIZE + 1)
    newSmallPageCount := uint((nsize - 1)/SMALL_PAGE_SIZE + 1)

    if nsize > osize {
        give_up_growth :: proc(data: ^JsWrapAlloc, optr: rawptr, osize: int, nsize: int, alignment: int) -> ([]byte, mem.Allocator_Error) {
            nptr, err := js_alloc(data, nsize, alignment)
            if err != nil do return nil, err
            mem.zero_slice(nptr)
            mem.copy(raw_data(nptr), optr, osize)
            js_free(data, optr, osize)
            return nptr, nil
        }

        if largePageOldTermIdx == largePageNewTermIdx {
            newBlocks := block_usage_bits_l(smallPageNewTermIdx) & ~block_usage_bits_l(smallPageOldTermIdx)
            if data.usedBlocks[largePageOldTermIdx-1] & newBlocks == 0 {
                data.usedBlocks[largePageOldTermIdx-1] |= newBlocks
                mem.zero_slice(([^]byte)(optr)[osize:nsize])
                return ([^]byte)(optr)[:nsize], nil
            } else {
                return give_up_growth(data, optr, osize, nsize, alignment)
            }
        } else {
            if data.usedBlocks[largePageOldTermIdx-1] & ~block_usage_bits_l(smallPageOldTermIdx) != 0 {
                return give_up_growth(data, optr, osize, nsize, alignment)
            }

            for i in (largePageOldTermIdx)..<(largePageNewTermIdx-1) {
                if i >= len(data.usedBlocks) {
                    newPages := largePageNewTermIdx - i

                    for j in 0..<newPages do append_elem(&data.usedBlocks, 0)

                    prev_page_count := intrinsics.wasm_memory_grow(0, uintptr(newPages))
                    if prev_page_count < 0 {
                        return nil, .Out_Of_Memory
                    }
                    break
                }

                if data.usedBlocks[i] != 0 do return give_up_growth(data, optr, osize, nsize, alignment)
            }

            if data.usedBlocks[largePageNewTermIdx-1] & block_usage_bits_l(smallPageNewTermIdx) != 0 {
                return give_up_growth(data, optr, osize, nsize, alignment)
            }

            data.usedBlocks[largePageOldTermIdx-1] |= ~block_usage_bits_l(smallPageOldTermIdx)
            for i in (largePageOldTermIdx)..<(largePageNewTermIdx-1) {
                data.usedBlocks[i] |= block_usage_bits_r(SMALL_PER_LARGE)
            }
            data.usedBlocks[largePageNewTermIdx-1] |= block_usage_bits_l(smallPageNewTermIdx)

            return ([^]byte)(optr)[:nsize], nil
        }
    } else {
        startOfFree := uintptr((largePageNewTermIdx-1)*LARGE_PAGE_SIZE + (smallPageNewTermIdx)*SMALL_PAGE_SIZE + uint(data.firstPage*LARGE_PAGE_SIZE))
        sizeOfFree := int(ptrn + uintptr(data.firstPage*LARGE_PAGE_SIZE) + uintptr(osize) - startOfFree)
        js_free(data, rawptr(startOfFree), sizeOfFree)

        return ([^]byte)(optr)[:nsize], nil
    }

    return nil, nil
}

js_wrap_alloc_proc :: proc(
    allocator_data: rawptr, 
    mode: mem.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr, 
    old_size: int,
    loc := #caller_location,
) -> ([]byte, mem.Allocator_Error) {

    data := cast(^JsWrapAlloc)allocator_data

	switch mode {
	case .Alloc:
        r, err := js_alloc(data, size, alignment)
        fmt.println("Alloc'd: ", size, len(r), uintptr(&r[0]), "-", uintptr(&r[len(r)-1]))
        print_block_usage(data)
        if err != nil do return nil, err
        else do return mem.zero_slice(r), nil
	case .Alloc_Non_Zeroed:
        return js_alloc(data, size, alignment)
	case .Resize:
        r, err := js_resize(data, old_memory, old_size, size, alignment)
        fmt.println("Resized: ", old_memory, old_size, size, alignment, uintptr(&r[0]), "-", uintptr(&r[len(r)-1]))
        print_block_usage(data)
        return r, err
	case .Free:
        if old_memory == nil do return nil, nil
        js_free(data, old_memory, old_size)
        fmt.println("Freed: ", old_memory, old_size)
        print_block_usage(data)
        return nil, nil
	case .Free_All:

	case .Query_Features:
        set := (^mem.Allocator_Mode_Set)(old_memory)
        if set != nil {
            set^ = {.Alloc, .Alloc_Non_Zeroed, .Resize, .Free, .Query_Features}
        }

	case .Query_Info:
    }

	return nil, nil
}

@(require_results)
js_wrap_allocator :: proc(data: ^JsWrapAlloc) -> mem.Allocator {
	return mem.Allocator{
		procedure = js_wrap_alloc_proc,
		data = data,
	}
}

print_block_usage :: proc(data: ^JsWrapAlloc) {
    blocks := data.usedBlocks

    for block in blocks {
        for j in 0..<(SMALL_PER_LARGE/4) {
            mask := block_usage_bits_l(4) >> uint(j*4)
            masked := block & mask
            masked >>= SMALL_PER_LARGE - uint(j*4) - 4

            switch masked {
                case 0b0000: fmt.print('_')
                case 0b1000: fmt.print('▖')
                case 0b0100: fmt.print('▗')
                case 0b1100: fmt.print('▄')
                case 0b0010: fmt.print('▘')
                case 0b1010: fmt.print('▌')
                case 0b0110: fmt.print('▚')
                case 0b1110: fmt.print('▙')
                case 0b0001: fmt.print('▝')
                case 0b1001: fmt.print('▞')
                case 0b0101: fmt.print('▐')
                case 0b1101: fmt.print('▟')
                case 0b0011: fmt.print('▀')
                case 0b1011: fmt.print('▛')
                case 0b0111: fmt.print('▜')
                case 0b1111: fmt.print('█')
            }
        }

        fmt.print(' ')
    }
    fmt.println()
}
