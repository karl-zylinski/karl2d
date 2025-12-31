___The first beta is almost here! Come back in a day or two...___

<img width="328" height="64" alt="karl2d_logo" src="https://github.com/user-attachments/assets/5ebd43c8-5a1d-4864-b8eb-7ce4b6a5dba0" />

Karl2D is a library for creating 2D games using the Odin programming language. The focus is on being fun and beginner-friendly, without the beginner-friendliness causing issues when you need to ship the game.

See [karl2d.doc.odin](https://github.com/karl-zylinski/karl2d/blob/master/karl2d.doc.odin) for an API overview.

Here's a minimal "Hello world" program:

```odin
package hello_world

import k2 "karl2d"
import "core:log"

main :: proc() {
	context.logger = log.create_console_logger()
	k2.init(1920, 1080, "Hellope!")

	for !k2.shutdown_wanted() {
		k2.new_frame()
		k2.process_events()
		k2.clear(k2.LIGHT_BLUE)
		k2.draw_text("Hellope!", {10, 10}, 100, k2.BLACK)
		k2.present()
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}
```

See the [examples](https://github.com/karl-zylinski/karl2d/tree/master/examples) folder for a wide variety of example programs.

Discuss and get help in the #karl2d channel [on my Discord server](https://discord.gg/4FsHgtBmFK).

## FIRST BETA

Karl2D is currently in its FIRST BETA period. This first beta has these features:
- Rendering of shapes, textures and text with automatic batching
- Support for shaders and cameras
- Windows support (D3D11 and OpenGL)
- Web support (WebGL, no emscripten needed!)
- Input: Mouse, keyboard, gamepad

This first beta does NOT have the following features, but they are planned in the order stated:
- Linux
- Sound
- System for cross-compiling shaders between different backends (HLSL, GLSL etc)
- Mac (metal)

## Feedback wanted
Here are some things I want to get feedback on:
- Is the `k2.new_frame()` concept OK? I was thinking of merging `new_frame()` and `process_events()`,
  but something tells me that some people may want to move their event processing around. Initially
  I was toying with the idea to have the user use `core:time` and figure out `dt` etc themselves,
  but that was not good for first-user experience.

- How do people think that DPI scaling should work? I've had bad experiences with high DPI mode
  Raylib. So I've gone for an idea where you always get everything in native coords and then you
  scale yourself using the number returned by `k2.get_window_scale()`

- Because of how web builds need `init` and `step` to be split up, I also split the examples up this
  way, so we can use them both on desktop and on web. This sometimes made them a bit more chatty.
  For example, I had to move some variables to the global scope. Should I approach this differently?

- Is it annoying that the documentation file `karl2d.doc.odin` has a real `.odin` file extension? I like that it gets syntax highlight for everyone etc. But it can also be a bit disruptive it "go to symbol" etc. Perhaps I should chance it to `.odin_doc` or something.

Join my Discord server and let me know in the #karl2d channel what you think! Here's the invite: https://discord.gg/4FsHgtBmFK

## Is this a Raylib clone?

The API was originally based on Raylib API, because I like that API. But I have changed things I don't like about Raylib and made the API more Odin-friendly. The implementation is meant to have as few dependencies as possible (mostly `core` libs and some libraries from `vendor`). The web builds do not need emscripten, it uses Odin's js_wasm32 target.

Since [I have shipped an actual game using Odin + Raylib](https://store.steampowered.com/app/2781210/CAT__ONION/), I am in a good position to know what worked well and what worked less well. I have tried to put that experience into this library.

## Have fun!

Logo by chris_php
