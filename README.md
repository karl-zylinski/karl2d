<img width="328" height="64" alt="karl2d_logo" src="https://github.com/user-attachments/assets/5ebd43c8-5a1d-4864-b8eb-7ce4b6a5dba0" />

Karl2D is a library for creating 2D games using the Odin programming language. The focus is on making 2D gamdev fun, fast and beginner friendly. All that, while using as few dependencies as I can. Less dependencies, less problems when you need to ship the game!

See [karl2d.doc.odin](https://github.com/karl-zylinski/karl2d/blob/master/karl2d.doc.odin) for an API overview.

Here's a minimal "Hello world" program:

```odin
package hello_world

import k2 "karl2d"

main :: proc() {
	k2.init(1280, 720, "Greetings from Karl2D!")

	for k2.update() {
		k2.clear(k2.LIGHT_BLUE)
		k2.draw_text("Hellope!", {50, 50}, 100, k2.DARK_BLUE)
		k2.present()
	}

	k2.shutdown()
}
```

See the [examples](https://github.com/karl-zylinski/karl2d/tree/master/examples) folder for a wide variety of example programs.

Some examples are available as live web builds: [minimal](https://zylinski.se/karl2d/minimal/), [camera](https://zylinski.se/karl2d/camera/), [box2d](https://zylinski.se/karl2d/box2d/), [fonts](https://zylinski.se/karl2d/fonts/), [gamepad](https://zylinski.se/karl2d/gamepad/), [mouse](https://zylinski.se/karl2d/mouse/), [render_texture](https://zylinski.se/karl2d/render_texture/), [snake](https://zylinski.se/karl2d/snake/).

Discuss and get help in the #karl2d channel [on my Discord server](https://discord.gg/4FsHgtBmFK).

## Beta 2

Karl2D is currently in its SECOND BETA period. If you finy _any_ issues, then please create an issue here on GitHub!

Beta 2 has these features:
- Rendering of shapes, textures and text with automatic batching
- Support for shaders and cameras
- Windows support (D3D11 and OpenGL)
- Mac support (OpenGL)
- Linux support (OpenGL)
- Web support (WebGL, no emscripten needed!)
- Input: Mouse, keyboard, gamepad

>[!WARNING]
>Beta 2 does NOT have the following features, but they are planned in the order stated:
>- Sound
>- System for cross-compiling shaders between different backends (HLSL, GLSL, GLSL ES, MSL etc)
>- Metal rendering backend for Mac (OpenGL already works)
>
> When I've gotten through this list, then the library is close to `1.0`

>[!WARNING]
>As this is a beta test version, changes to the API will happen.

## How to make a web build of your game

There's a build script located in the `build_web` folder. Run it like this:

```
odin run build_web -- your_game_path
```

The web build will end up in `your_game_path/bin/web`.


>[!NOTE]
>You can run the build_web script from anywhere by doing:
>`odin run path/to/karl2d/build_web -- your_game_path`

>[!WARNING]
>On Linux / Mac you may need to install some `lld` package that contains the `wasm-ld` linker. It's included with Odin on Windows.

It requires that you game contains a `init` procedure and a `step` procedure. The `init` procedure is called once on startup and the `step` procedure will be called every frame of your game.

Also, see the `minimal_hello_world_web` example: https://github.com/karl-zylinski/karl2d/blob/master/examples/minimal_hello_world_web/minimal_hello_world_web.odin

The `build_web` tool will copy `odin.js` file from `<odin>/core/sys/wasm/js/odin.js` into the `bin/web folder`. It will also copy a HTML index file into that folder.

It will also create a `build/web` folder. That's the package it actually builds. It contains a bit of wrapper code that then calls the `init` and `step` functions of your game. The result of building the wrapper (and your game) is a `main.wasm` file that also ends up in `bin/web`.

Launch your game by opening `bin/web/index.html` in a browser.

>[!NOTE]
>To get better in-browser debug symbols, you can add `-debug` when running the `build_web` script:
>`odin run build_web -- your_game_path -debug`
>Note that it comes after the `--`: That's the flags that get sent on to the `build_web` program! There are also `-o:speed/size` flags to turn on optimization.

>[!WARNING]
>If you open the `index.html` file and see nothing, then there might be an error about "cross site policy" stuff in the browser's console. In that case you can use python to run a local web-server and access the web build through it. Run `python -m http.server` in the `bin/web` folder and then navigate to `https://localhost:8000`.

## Architecture notes

The platform-independent parts and the API lives in `karl2d.odin`

`karl2d.odin` in turn has a window interface and a rendering backend.

The window interface depends on the operating system. I do not use anything like GLFW in order to abstract away window creation and event handling. Less libraries between you and the OS, less trouble when shipping!

The rendering backend tells Karl2D how to talk to the GPU. I currently support three rendering APIs: D3D11, OpenGL and WebGL. On some platforms you have multiple choices, for exmaple on Windows you can use both D3D11 and OpenGL.

The platform independent code in `karl2d.odin` creates a list of vertices for each batch it needs to render. That's done independently of the rendering backend. The backend is just fed that list, along with information about what shader and such to use.

The web builds do not need emscripten, instead I've written a WebGL backend and make use of the official Odin JS runtime. This makes building for the web easier and less error-prone.

## Troubleshooting

### Linux build error: libudev is missing

Try installing a package such as `systemd-devel` or `systemd-dev`.

## Contributing and Pull Request rules

Are you interested in helping with Karl2D development? Thank you! You can look at open issues here on GitHub. You get your contributions into the project using a Pull Request.

You can always open a _draft_ Pull Request and work on your stuff in there. There are no rules for draft pull requests. However, when you want to turn your draft into a ready-for-review Pull Request (which means that I might look at it), then please follow these rules:

1. Make sure that the code you submit is working and tested.
2. Do not submit "basic" or "rudimentary" code that needs further work to actually be finished. Finish the code to the best of your abilities.
3. Do not modify any code that is unrelated to your changes. That just makes reviewing your code harder: I'll have a hard time seeing what you actually did. Do not use auto formatters such as odinfmt.
4. If you commit changes that were unintended, just do additional commits that undo them. Don't worry about polluting the commit history: I will do a "squash merge" of your Pull Request. Just make sure that the diff in the "Files changed" tab looks tidy.
5. The GitHub testing actions will make sure that the [`karl2d.doc.odin`](https://github.com/karl-zylinski/karl2d/blob/master/karl2d.doc.odin) file is up-to-date. I enforce this because it will make you see if you changed any parts of the user-facing API. This way we find API-breaking changes before they are merged. Regenerate `karl2d.doc.odin` by running `odin run tools/api_doc_builder` in the root folder of the repository.
6. Finally, about code style: Make sure that the code follows the same style as in [`karl2d.odin`](https://github.com/karl-zylinski/karl2d/blob/master/karl2d.odin):
	- Please look through that file and pay attention to how characters such as `:` `=`, `(` `{` etc are placed.
	- Use tabs, not spaces.
	- Lines cannot be longer than 100 characters. See the `init` proc in [`karl2d.odin`](https://github.com/karl-zylinski/karl2d/blob/master/karl2d.odin) for an example of how to split up procedure signatures that are too long. That proc also shows how to write API comments. Use a _ruler_ in your editor to make it easy to spot long lines.

## Have fun!

Logo by chris_php
