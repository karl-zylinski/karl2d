___This library is NOT ready for use!___

This is a WIP library for creating 2D games using the Odin Programming Language. The API is heavily inspired by Raylib, and in its current state it wraps Raylib. In the long term the library will have its own implementation that only uses `core` libraries and rendering APIs from `vendor`.

The name _karlib_ will most likely change.

Big upcoming tasks:
* Port raylib examples to figure out API surface
* Write a Windows + D3D11 backend (no more Raylib)

## Why does it wrap Raylib?

I know Raylib very well and it made sense for me to create a wrapper for it, tweak the API and at some point rewrite the implementation without Raylib.
