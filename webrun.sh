#!/bin/sh

./.webrun.py &
find | grep '.*.odin' | entr odin build omui.odin -file -target:js_wasm32
