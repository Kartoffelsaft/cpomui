setTimeout(async function(){
    class WasmMemoryInterface {
        constructor() {
            this.memory = null;
            this.exports = null;
            this.listenerMap = {};
        }

        setMemory(memory) {
            this.memory = memory;
        }

        setExports(exports) {
            this.exports = exports;
        }

        get mem() {
            return new DataView(this.memory.buffer);
        }


        loadF32Array(addr, len) {
            let array = new Float32Array(this.memory.buffer, addr, len);
            return array;
        }
        loadF64Array(addr, len) {
            let array = new Float64Array(this.memory.buffer, addr, len);
            return array;
        }
        loadU32Array(addr, len) {
            let array = new Uint32Array(this.memory.buffer, addr, len);
            return array;
        }
        loadI32Array(addr, len) {
            let array = new Int32Array(this.memory.buffer, addr, len);
            return array;
        }


        loadU8(addr) { return this.mem.getUint8  (addr, true); }
        loadI8(addr) { return this.mem.getInt8   (addr, true); }
        loadU16(addr) { return this.mem.getUint16 (addr, true); }
        loadI16(addr) { return this.mem.getInt16  (addr, true); }
        loadU32(addr) { return this.mem.getUint32 (addr, true); }
        loadI32(addr) { return this.mem.getInt32  (addr, true); }
        loadU64(addr) {
            const lo = this.mem.getUint32(addr + 0, true);
            const hi = this.mem.getUint32(addr + 4, true);
            return lo + hi*4294967296;
        };
        loadI64(addr) {
            // TODO(bill): loadI64 correctly
            const lo = this.mem.getUint32(addr + 0, true);
            const hi = this.mem.getUint32(addr + 4, true);
            return lo + hi*4294967296;
        };
        loadF32(addr)  { return this.mem.getFloat32(addr, true); }
        loadF64(addr)  { return this.mem.getFloat64(addr, true); }
        loadInt(addr)  { return this.mem.getInt32  (addr, true); }
        loadUint(addr) { return this.mem.getUint32 (addr, true); }

        loadPtr(addr) { return this.loadUint(addr); }

        loadBytes(ptr, len) {
            return new Uint8Array(this.memory.buffer, ptr, len);
        }

        loadString(ptr, len) {
            const bytes = this.loadBytes(ptr, len);
            return new TextDecoder("utf-8").decode(bytes);
        }

        storeU8(addr, value)  { this.mem.setUint8  (addr, value, true); }
        storeI8(addr, value)  { this.mem.setInt8   (addr, value, true); }
        storeU16(addr, value) { this.mem.setUint16 (addr, value, true); }
        storeI16(addr, value) { this.mem.setInt16  (addr, value, true); }
        storeU32(addr, value) { this.mem.setUint32 (addr, value, true); }
        storeI32(addr, value) { this.mem.setInt32  (addr, value, true); }
        storeU64(addr, value) {
            this.mem.setUint32(addr + 0, value, true);
            this.mem.setUint32(addr + 4, Math.floor(value / 4294967296), true);
        }
        storeI64(addr, value) {
            // TODO(bill): storeI64 correctly
            this.mem.setUint32(addr + 0, value, true);
            this.mem.setUint32(addr + 4, Math.floor(value / 4294967296), true);
        }
        storeF32(addr, value)  { this.mem.setFloat32(addr, value, true); }
        storeF64(addr, value)  { this.mem.setFloat64(addr, value, true); }
        storeInt(addr, value)  { this.mem.setInt32  (addr, value, true); }
        storeUint(addr, value) { this.mem.setUint32 (addr, value, true); }
    };

    let currentLine = "";
    writeToConsole = (str, err) => {
        if (str.includes('\n')) {
            if (err) {console.error(currentLine + str);}
            else {console.log((currentLine + str).trim());}
            currentLine = "";
        } else {
            currentLine = currentLine + str;
        }
    }

    let wasmMemoryInterface = new WasmMemoryInterface();
    let eventTempData = {};
    let eventStringBuffer = {detached: true};
    let returnString = new Uint8Array();

    let canvas = document.querySelector("canvas");
    let canvasCtx = canvas.getContext("2d");
    canvasCtx.font = "14px Cozette"
    setInterval(() => {
        if (canvas.width != window.innerWidth
        ||  canvas.height != window.innerHeight) {
            canvas.width  = window.innerWidth;
            canvas.height = window.innerHeight;
            canvasCtx.font = "14px Cozette"
        }
    }, 1000);

    let loopId = -1;
    let loopFn = -1;

    let obj = await WebAssembly.instantiateStreaming(fetch("omui.wasm"), {
        "canvas": { 
            memory: new WebAssembly.Memory({initial: 1, maximum: 9999, shared: true}),
            js_save_file: (sFileName, lFileName, sContent, lContent) => {
                const filename = wasmMemoryInterface.loadString(sFileName, lFileName);
                const content  = wasmMemoryInterface.loadString(sContent , lContent );

                var pom = document.createElement('a');
                pom.setAttribute('href', 'data:application:octet-stream,' + encodeURIComponent(content));
                pom.setAttribute('download', filename);
                pom.click();
            },
            js_open_file_dialogue: (cb) => {
                var inp = document.createElement("input");
                inp.type = "file";

                inp.onchange = (e) => {
                    var file = e.target.files[0];
                    var reader = new FileReader();
                    reader.readAsText(file, "UTF-8");
                    reader.onload = (re) => {
                        returnString = new TextEncoder("UTF-8").encode(re.target.result);
                        wasmMemoryInterface.exports.call_fn(cb);
                    }
                }

                let verifyUserInput = () => {inp.click()}
                canvas.addEventListener("pointerup", verifyUserInput, {once: true});
            },
            print_something: (s, l) => {
                const str = wasmMemoryInterface.loadString(s, l);
                console.log(str);
            },
            load_event_string_buffer: (p, l) => {
                eventStringBuffer = wasmMemoryInterface.loadBytes(p, l);
            },
            get_return_string_length: () => {
                return returnString.length;
            },
            get_return_string: (p, l) => {
                wasmMemoryInterface.loadBytes(p, l).set(returnString)
            },
            js_set_target_framerate: (framerate) => {
                if (loopFn !== -1) {
                    clearInterval(loopId);
                    setInterval(wasmMemoryInterface.exports.call_fn, 1000 / framerate, loopFn)
                }
            },
            set_loop_target: (t) => {
                loopFn = t
                loopId = setInterval(wasmMemoryInterface.exports.call_fn, 1000 / 60, t);
            },
            js_text_width: (s, l) => {
                const str = wasmMemoryInterface.loadString(s, l);
                return canvasCtx.measureText(str).width
            },
            js_text_height: () => {
                const measure = canvasCtx.measureText("|");
                return measure.fontBoundingBoxAscent + measure.fontBoundingBoxDescent;
            },
            js_get_width : () => {return canvas.width ;},
            js_get_height: () => {return canvas.height;},
            is_window_focused: () => {return document.hasFocus()},
            fill_canvas: (color_s, color_l) => {
                canvasCtx.fillStyle = wasmMemoryInterface.loadString(color_s, color_l);
                canvasCtx.fillRect(0, 0, canvas.width, canvas.height);
            },
            fill_rect: (x, y, w, h, color_s, color_l) => {
                canvasCtx.fillStyle = wasmMemoryInterface.loadString(color_s, color_l);
                canvasCtx.fillRect(x, y, w, h);
            },
            draw_text: (x, y, s, l, color_s, color_l) => {
                const str = wasmMemoryInterface.loadString(s, l);
                canvasCtx.fillStyle = wasmMemoryInterface.loadString(color_s, color_l);
                canvasCtx.fillText(str, x, y + canvasCtx.measureText(str).fontBoundingBoxAscent);
            },
        },
        "odin_env": {
            write: (fd, ptr, len) => {
                const str = wasmMemoryInterface.loadString(ptr, len);
                if (fd == 1) {
                    writeToConsole(str, false);
                    return;
                } else if (fd == 2) {
                    writeToConsole(str, true);
                    return;
                } else {
                    throw new Error("Invalid fd to 'write'" + stripNewline(str));
                }
            },
            trap: () => { throw new Error() },
            alert: (ptr, len) => { alert(wasmMemoryInterface.loadString(ptr, len)) },
            abort: () => { Module.abort() },
            evaluate: (str_ptr, str_len) => { eval.call(null, wasmMemoryInterface.loadString(str_ptr, str_len)); },

            time_now: () => {
                // convert ms to ns
                return Date.now() * 1e6;
            },
            tick_now: () => {
                // convert ms to ns
                return performance.now() * 1e6;
            },
            time_sleep: (duration_ms) => {
                if (duration_ms > 0) {
                    // TODO(bill): Does this even make any sense?
                }
            },

            sqrt:    (x) => Math.sqrt(x),
            sin:     (x) => Math.sin(x),
            cos:     (x) => Math.cos(x),
            pow:     (x, power) => Math.pow(x, power),
            fmuladd: (x, y, z) => x*y + z,
            ln:      (x) => Math.log(x),
            exp:     (x) => Math.exp(x),
            ldexp:   (x) => Math.ldexp(x),
        },
        "odin_dom": {
            init_event_raw: (ep) => {
                const W = 4;
                let offset = ep;
                let off = (amount, alignment) => {
                    if (alignment === undefined) {
                        alignment = Math.min(amount, W);
                    }
                    if (offset % alignment != 0) {
                        offset += alignment - (offset%alignment);
                    }
                    let x = offset;
                    offset += amount;
                    return x;
                };

                let wmi = wasmMemoryInterface;

                let e = eventTempData.event;

                wmi.storeU32(off(4), eventTempData.name_code);
                if (e.target == document) {
                    wmi.storeU32(off(4), 1);
                } else if (e.target == window) {
                    wmi.storeU32(off(4), 2);
                } else {
                    wmi.storeU32(off(4), 0);
                }
                if (e.currentTarget == document) {
                    wmi.storeU32(off(4), 1);
                } else if (e.currentTarget == window) {
                    wmi.storeU32(off(4), 2);
                } else {
                    wmi.storeU32(off(4), 0);
                }

                wmi.storeUint(off(W), eventTempData.id_ptr);
                wmi.storeUint(off(W), eventTempData.id_len);

                wmi.storeU32(off(W), 0); // damn struct alignment

                wmi.storeF64(off(8), e.timeStamp*1e-3);

                wmi.storeU8(off(1), e.eventPhase);
                let options = 0;
                if (!!e.bubbles)    { options |= 1<<0; }
                if (!!e.cancelable) { options |= 1<<1; }
                if (!!e.composed)   { options |= 1<<2; }
                wmi.storeU8(off(1), options);
                wmi.storeU8(off(1), !!e.isComposing);
                wmi.storeU8(off(1), !!e.isTrusted);

                let base = off(0, 8);
                if (e instanceof WheelEvent) {
                    wmi.storeF64(off(8), e.deltaX);
                    wmi.storeF64(off(8), e.deltaY);
                    wmi.storeF64(off(8), e.deltaZ);
                    wmi.storeU32(off(4), e.deltaMode);
                } else if (e instanceof MouseEvent) {
                    wmi.storeI64(off(8), e.screenX);
                    wmi.storeI64(off(8), e.screenY);
                    wmi.storeI64(off(8), e.clientX);
                    wmi.storeI64(off(8), e.clientY);
                    wmi.storeI64(off(8), e.offsetX);
                    wmi.storeI64(off(8), e.offsetY);
                    wmi.storeI64(off(8), e.pageX);
                    wmi.storeI64(off(8), e.pageY);
                    wmi.storeI64(off(8), e.movementX);
                    wmi.storeI64(off(8), e.movementY);

                    wmi.storeU8(off(1), !!e.ctrlKey);
                    wmi.storeU8(off(1), !!e.shiftKey);
                    wmi.storeU8(off(1), !!e.altKey);
                    wmi.storeU8(off(1), !!e.metaKey);

                    wmi.storeI16(off(2), e.button);
                    wmi.storeU16(off(2), e.buttons);
                } else if (e instanceof KeyboardEvent) {
                    if (eventStringBuffer.detached === true) {
                        obj.instance.exports.request_new_event_string_buffer();
                    }
                    eventStringBuffer.set(new TextEncoder("utf-8").encode(e.key + e.code))
                    wmi.storeUint(off(W), eventStringBuffer.byteOffset);
                    wmi.storeUint(off(W), e.key.length);
                    wmi.storeUint(off(W), eventStringBuffer.byteOffset + e.key.length);
                    wmi.storeUint(off(W), e.code.length);
                    //let keyOffset = off(W*2, W);
                    //let codeOffet = off(W*2, W);
                    wmi.storeU8(off(1), e.location);

                    wmi.storeU8(off(1), !!e.ctrlKey);
                    wmi.storeU8(off(1), !!e.shiftKey);
                    wmi.storeU8(off(1), !!e.altKey);
                    wmi.storeU8(off(1), !!e.metaKey);

                    wmi.storeU8(off(1), !!e.repeat);
                } else if (e instanceof Event) {
                    if ('scrollX' in e) {
                        wmi.storeF64(off(8), e.scrollX);
                        wmi.storeF64(off(8), e.scrollY);
                    }
                }
            },

            add_event_listener: (id_ptr, id_len, name_ptr, name_len, name_code, data, callback, use_capture) => {
                let id = wasmMemoryInterface.loadString(id_ptr, id_len);
                let name = wasmMemoryInterface.loadString(name_ptr, name_len);
                let element = document.getElementById(id);
                if (element == undefined) {
                    return false;
                }

                let listener = (e) => {
                    const odin_ctx = wasmMemoryInterface.exports.default_context_ptr();
                    eventTempData.id_ptr = id_ptr;
                    eventTempData.id_len = id_len;
                    eventTempData.event = e;
                    eventTempData.name_code = name_code;
                    wasmMemoryInterface.exports.odin_dom_do_event_callback(data, callback, odin_ctx);
                };
                wasmMemoryInterface.listenerMap[{data: data, callback: callback}] = listener;
                element.addEventListener(name, listener, !!use_capture);
                return true;
            },

            remove_event_listener: (id_ptr, id_len, name_ptr, name_len, data, callback) => {
                let id = wasmMemoryInterface.loadString(id_ptr, id_len);
                let name = wasmMemoryInterface.loadString(name_ptr, name_len);
                let element = document.getElementById(id);
                if (element == undefined) {
                    return false;
                }

                let listener = wasmMemoryInterface.listenerMap[{data: data, callback: callback}];
                if (listener == undefined) {
                    return false;
                }
                element.removeEventListener(name, listener);
                return true;
            },


            add_window_event_listener: (name_ptr, name_len, name_code, data, callback, use_capture) => {
                let name = wasmMemoryInterface.loadString(name_ptr, name_len);
                let element = window;
                let listener = (e) => {
                    const odin_ctx = wasmMemoryInterface.exports.default_context_ptr();
                    eventTempData.id_ptr = 0;
                    eventTempData.id_len = 0;
                    eventTempData.event = e;
                    eventTempData.name_code = name_code;
                    wasmMemoryInterface.exports.odin_dom_do_event_callback(data, callback, odin_ctx);
                };
                wasmMemoryInterface.listenerMap[{data: data, callback: callback}] = listener;
                element.addEventListener(name, listener, !!use_capture);
                return true;
            },

            remove_window_event_listener: (name_ptr, name_len, data, callback) => {
                let name = wasmMemoryInterface.loadString(name_ptr, name_len);
                let element = window;
                let key = {data: data, callback: callback};
                let listener = wasmMemoryInterface.listenerMap[key];
                if (!listener) {
                    return false;
                }
                wasmMemoryInterface.listenerMap[key] = undefined;

                element.removeEventListener(name, listener);
                return true;
            },

            event_stop_propagation: () => {
                if (eventTempData && eventTempData.event) {
                    eventTempData.event.eventStopPropagation();
                }
            },
            event_stop_immediate_propagation: () => {
                if (eventTempData && eventTempData.event) {
                    eventTempData.event.eventStopImmediatePropagation();
                }
            },
            event_prevent_default: () => {
                if (eventTempData && eventTempData.event) {
                    eventTempData.event.preventDefault();
                }
            },

            dispatch_custom_event: (id_ptr, id_len, name_ptr, name_len, options_bits) => {
                let id = wasmMemoryInterface.loadString(id_ptr, id_len);
                let name = wasmMemoryInterface.loadString(name_ptr, name_len);
                let options = {
                    bubbles:   (options_bits & (1<<0)) !== 0,
                    cancelabe: (options_bits & (1<<1)) !== 0,
                    composed:  (options_bits & (1<<2)) !== 0,
                };

                let element = document.getElementById(id);
                if (element) {
                    element.dispatchEvent(new Event(name, options));
                    return true;
                }
                return false;
            },

            get_element_value_f64: (id_ptr, id_len) => {
                let id = wasmMemoryInterface.loadString(id_ptr, id_len);
                let element = document.getElementById(id);
                return element ? element.value : 0;
            },
            get_element_value_string: (id_ptr, id_len, buf_ptr, buf_len) => {
                let id = wasmMemoryInterface.loadString(id_ptr, id_len);
                let element = document.getElementById(id);
                if (element) {
                    let str = element.value;
                    if (buf_len > 0 && buf_ptr) {
                        let n = Math.min(buf_len, str.length);
                        str = str.substring(0, n);
                        this.mem.loadBytes(buf_ptr, buf_len).set(new TextEncoder("utf-8").encode(str))
                        return n;
                    }
                }
                return 0;
            },
            get_element_value_string_length: (id_ptr, id_len) => {
                let id = wasmMemoryInterface.loadString(id_ptr, id_len);
                let element = document.getElementById(id);
                if (element) {
                    return element.value.length;
                }
                return 0;
            },
            get_element_min_max: (ptr_array2_f64, id_ptr, id_len) => {
                let id = wasmMemoryInterface.loadString(id_ptr, id_len);
                let element = document.getElementById(id);
                if (element) {
                    let values = wasmMemoryInterface.loadF64Array(ptr_array2_f64, 2);
                    values[0] = element.min;
                    values[1] = element.max;
                }
            },
            set_element_value_f64: (id_ptr, id_len, value) => {
                let id = wasmMemoryInterface.loadString(id_ptr, id_len);
                let element = document.getElementById(id);
                if (element) {
                    element.value = value;
                }
            },
            set_element_value_string: (id_ptr, id_len, value_ptr, value_id) => {
                let id = wasmMemoryInterface.loadString(id_ptr, id_len);
                let value = wasmMemoryInterface.loadString(value_ptr, value_len);
                let element = document.getElementById(id);
                if (element) {
                    element.value = value;
                }
            },


            get_bounding_client_rect: (rect_ptr, id_ptr, id_len) => {
                let id = wasmMemoryInterface.loadString(id_ptr, id_len);
                let element = document.getElementById(id);
                if (element) {
                    let values = wasmMemoryInterface.loadF64Array(rect_ptr, 4);
                    let rect = element.getBoundingClientRect();
                    values[0] = rect.left;
                    values[1] = rect.top;
                    values[2] = rect.right  - rect.left;
                    values[3] = rect.bottom - rect.top;
                }
            },
            window_get_rect: (rect_ptr) => {
                let values = wasmMemoryInterface.loadF64Array(rect_ptr, 4);
                values[0] = window.screenX;
                values[1] = window.screenY;
                values[2] = window.screen.width;
                values[3] = window.screen.height;
            },

            window_get_scroll: (pos_ptr) => {
                let values = wasmMemoryInterface.loadF64Array(pos_ptr, 2);
                values[0] = window.scrollX;
                values[1] = window.scrollY;
            },
            window_set_scroll: (x, y) => {
                window.scroll(x, y);
            },

            device_pixel_ratio: () => {
                return window.devicePixelRatio;
            },

        },
    });

    wasmMemoryInterface.setExports(obj.instance.exports);
    wasmMemoryInterface.setMemory(obj.instance.exports.memory);

    console.log(obj);
    obj.instance.exports._start();
    obj.instance.exports._end();

}, 0);
