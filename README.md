<img width="328" height="64" alt="karl2d_logo" src="https://github.com/user-attachments/assets/5ebd43c8-5a1d-4864-b8eb-7ce4b6a5dba0" />

Karl2D is a library for creating 2D games using the Odin programming language. The focus is on making 2D gamdev fun, fast and beginner friendly.

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

Some examples are available as live web builds: [box2d](https://zylinski.se/karl2d/box2d/), [fonts](https://zylinski.se/karl2d/fonts/), [gamepad](https://zylinski.se/karl2d/gamepad/), [minimal](https://zylinski.se/karl2d/minimal/), [mouse](https://zylinski.se/karl2d/mouse/), [render_texture](https://zylinski.se/karl2d/render_texture/), [snake](https://zylinski.se/karl2d/snake/).

Discuss and get help in the #karl2d channel [on my Discord server](https://discord.gg/4FsHgtBmFK).

## FIRST BETA

Karl2D is currently in its FIRST BETA period. This first beta has these features:
- Rendering of shapes, textures and text with automatic batching
- Support for shaders and cameras
- Windows support (D3D11 and OpenGL)
- Web support (WebGL, no emscripten needed!)
- Input: Mouse, keyboard, gamepad

>[!WARNING]
>This first beta does NOT have the following features, but they are planned in the order stated:
>- Linux
>- Sound
>- System for cross-compiling shaders between different backends (HLSL, GLSL etc)
>- Mac (metal)

## Feedback wanted
Here are some things I want to get feedback on during this first beta:
- Is the `k2.new_frame()` concept OK? It sets the "frame time" and clears some frame-specific state. I was thinking of merging `new_frame()` and `process_events()`,
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

## How to make a web build of your game

There's a build script located in the `build_web` folder. Run it like this:

```
odin run build_web -- your_game_path
```

The web build will end up in `your_game_path/bin/web`.

It requires that you game contains a `main` procedure and a `step` procedure. The `main` procedure is called once on startup and the `step` procedure will be called every frame of your game.

>[!WARNING]
>When making web builds, make sure your `main` procedure does not have a "main loop" in it. That will hang the browser tab when your game starts.

Also, see the `minimal_web` example: https://github.com/karl-zylinski/karl2d/blob/master/examples/minimal_web/minimal_web.odin

The `build_web` tool will copy `odin.js` file from `<odin>/core/sys/wasm/js/odin.js` into the `bin/web folder`. It will also copy a HTML index file into that folder.

It will also create a `build/web` folder. That's the package it actually builds. It contains a bit of wrapper code that then calls the `main` and `step` functions of your game. The result of building the wrapper (and your game) is a `main.wasm` file that also ends up in `bin/web`.

Launch your game by opening `bin/web/index.html` in a browser.

## Architecture notes

The platform-independent parts and the main API lives in `karl2d.odin`

`karl2d.odin` in turn has a window interface and a rendering backend.

The window interface depends on the operating system. I do not use anything like GLFW in order to abstract away window creation and event handling. Less libraries between you and the OS, less trouble when shipping!

The rendering backend tells Karl2D how to talk to the GPU. I currently support three rendering APIs: D3D11, OpenGL and WebGL. On some platforms you have multiple choices, for exmaple on Windows you can use both D3D11 and OpenGL.

The platform independent code in `karl2d.odin` creates a list of vertices for each batch it needs to render. That's done independently of the rendering backend. The backend is just fed that list, along with information about what shader and such to use.

The web builds do not need emscripten, instead I've written a WebGL backend and make use of the official Odin JS runtime. This makes building for the web easier and less error-prone.

## Is this a Raylib clone?

The API was originally based on Raylib API, because I like that API. But I have changed things I don't like about Raylib and made the API more Odin-friendly. The implementation is meant to have as few dependencies as possible (mostly `core` libs and some libraries from `vendor`). The web builds do not need emscripten, it uses Odin's js_wasm32 target.

Since [I have shipped an actual game using Odin + Raylib](https://store.steampowered.com/app/2781210/CAT__ONION/), I am in a good position to know what worked well and what worked less well. I have tried to put that experience into this library.

## Have fun!

Logo by chris_php
