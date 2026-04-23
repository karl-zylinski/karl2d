<img width="400" alt="logo" src="https://github.com/user-attachments/assets/6dedd9e3-6965-46cb-afef-048470697f17" />

Make 2D games using the Odin Programming Language! Karl2D is a beginner friendly game creation library. It strives to minimize the number of dependencies, making you feel in control of the technology stack.

See [karl2d.doc.odin](https://github.com/karl-zylinski/karl2d/blob/master/karl2d.doc.odin) for an API overview.

Support the project by becoming a sponsor here on [GitHub](https://github.com/sponsors/karl-zylinski) or on [Patreon](https://patreon.com/karl_zylinski).

"Hello world" program (draws the text "Hellope!" in a window):

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

These examples are available as live web builds:
- [hellope](https://zylinski.se/karl2d/hellope/)
- [basics](https://zylinski.se/karl2d/basics/)
- [camera](https://zylinski.se/karl2d/camera/)
- [audio](https://zylinski.se/karl2d/audio/)
- [audio_positional](https://zylinski.se/karl2d/positional_audio/)
- [dual_grid_tilemap](https://zylinski.se/karl2d/dual_grid_tilemap/)
- [box2d](https://zylinski.se/karl2d/box2d/)
- [fonts](https://zylinski.se/karl2d/fonts/)
- [gamepad](https://zylinski.se/karl2d/gamepad/)
- [mouse](https://zylinski.se/karl2d/mouse/)
- [render_texture](https://zylinski.se/karl2d/render_texture/)
- [snake](https://zylinski.se/karl2d/snake/)

Discuss and get help in the #karl2d channel [on my Discord server](https://discord.gg/4FsHgtBmFK).

## Beta 3

Karl2D is currently in its THIRD BETA period. If you find _any_ issues, then please create an issue here on GitHub!

Beta 3 has these features:
- Rendering of shapes, textures and text with automatic batching
- Audio playback using custom software mixer
- Support for shaders and cameras
- Windows support (D3D11 and OpenGL)
- Mac support (OpenGL)
- Linux support (OpenGL)
- Web support (WebGL, no emscripten needed!)
- Input: Mouse, keyboard, gamepad

## Roadmap

- [Beta 4: Rendering improvements](https://github.com/karl-zylinski/karl2d/milestone/3)
- [Beta 5: Metal backend](https://github.com/karl-zylinski/karl2d/milestone/4)
- [Beta 6: Cross-API shader compiler](https://github.com/karl-zylinski/karl2d/milestone/5)
- 1.0

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

It requires that your game contains an `init` procedure and a `step` procedure. The `init` procedure is called once on startup and the `step` procedure will be called every frame of your game.

Also, see the [`minimal_hello_world_web.odin`](https://github.com/karl-zylinski/karl2d/blob/master/examples/minimal_hello_world_web/minimal_hello_world_web.odin) example.

The `build_web` tool will copy `odin.js` file from `<odin>/core/sys/wasm/js/odin.js` into the `bin/web folder`. It will also copy a HTML index file into that folder.

It will also create a `build/web` folder. That's the package it actually builds. It contains a bit of wrapper code that then calls the `init` and `step` functions of your game. The result of building the wrapper (and your game) is a `main.wasm` file that also ends up in `bin/web`.

Launch your game by opening `bin/web/index.html` in a browser.

>[!NOTE]
>To get better in-browser debug symbols, you can add `-debug` when running the `build_web` script:
>`odin run build_web -- your_game_path -debug`
>Note that it comes after the `--`: That's the flags that get sent on to the `build_web` program! There are also `-o:speed/size` flags to turn on optimization.

>[!WARNING]
>If you open the `index.html` file and see nothing, then there might be an error about "cross site policy" stuff in the browser's console. In that case you can use python to run a local web-server and access the web build through it. Run `python -m http.server` in the `bin/web` folder and then navigate to `https://localhost:8000`.

## Linux Dependencies

While Karl2D avoids big dependencies that add abstractions between the library and the OS, it still requires the installation of some dependencies on Linux.

- Linux: `libasound2-dev libgl1-mesa-dev libudev-dev libwayland-dev libegl1-mesa-dev` (names may vary per distribution)
- Web build on Linux: `lld`

This may sound like there are lots of dependencies -- But in reality it just means that this library talks directly to low-level libraries. If you use something like GLFW then GLFW in turn talks to these kinds of libraries. However, then you must hop into a C library in the debugger when you want to see those calls. This means that you can go deeper in the callstack using Karl2D without leaving the Odin code.

## Architecture notes

The platform-independent parts and the API lives in `karl2d.odin`.

`karl2d.odin` in turn has a window interface and a rendering backend.

The window interface depends on the operating system. I do not use anything like GLFW in order to abstract away window creation and event handling. Less libraries between you and the OS, less trouble when shipping!

The rendering backend tells Karl2D how to talk to the GPU. I currently support three rendering APIs: D3D11, OpenGL and WebGL. On some platforms you have multiple choices, for example on Windows you can use both D3D11 and OpenGL.

The platform independent code in `karl2d.odin` creates a list of vertices for each batch it needs to render. That's done independently of the rendering backend. The backend is just fed that list, along with information about what shader and such to use.

The web builds do not need emscripten, instead I've written a WebGL backend and make use of the official Odin JS runtime. This makes building for the web easier and less error-prone.

## Contributing and Pull Request rules

Are you interested in helping with Karl2D development? Thank you! You can look at open issues here on GitHub. You get your contributions into the project using a Pull Request.

You can always open a _draft_ Pull Request and work on your stuff in there. There are no rules for draft pull requests. When you want to turn your draft into a ready-for-review Pull Request, then please follow this rule checklist: https://github.com/karl-zylinski/karl2d/blob/master/.github/pull_request_template.md

## Have fun!
