___This library is NOT ready for use!___

Karl2D is a WIP library for creating 2D games using the Odin Programming Language.

The API is based on Raylib, but adapted to my tastes.

In its current state, Karl2D wraps Raylib. But in the long term the library will have its own implementation that only uses `core` libraries and rendering APIs from `vendor`.

Big upcoming tasks:
* Port raylib examples to figure out API surface
* Write a Windows + D3D11 backend (no more Raylib)

## Why does it wrap Raylib?

I know Raylib very well. I like it, but I would like to have something written in native Odin. Having a native library is great for debugging, among other reasons. There are a few things I'd like to change about Raylib as well. So this library is meant to solve all those things.

However, since I like Raylib, using something similar to its API is a good starting point. The steps towards a native Odin library independent of Raylib are:
- Wrap Raylib
- Modify the API to my tastes, within what is possible while still wrapping Raylib
- Write a new implementation that uses native OS windowing APIs and rendering APIs
- At this point I have more control and can further refine the API

## What features of Raylib will not be included?

* 3D
* Some maths things that can be found in Odin's core libs

Audio support isn't planned at first, but may be added later. Until then you can use `vendor:miniaudio` or similar.

I might skip the GetFrameTime / GetTime from Raylib and let the user use `core:time` instead.