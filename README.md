___This library is NOT ready for use!___

Karl2D is a work-in-progress library for creating 2D games using the Odin Programming Language.

The API is based on Raylib because I like that API. But the implementation is meant to have as few dependencies as possible (only `core` libs and rendering APIs in `vendor`). The API will not be identical to Raylib. I'll modify to fit Odin better etc.

## What features of Raylib will not be included?

* 3D
* Some maths things that can be found in Odin's core libs

Might no be included:
* Time management (use `core:time` instead)

## TODO

Here follows my near-future TODO list

* Do proper checks of vertex count and dispatch rendering when full
* Should we sort by depth?
* Load textures and somehow bind to shader -- split draw calls on texture switch -- needs a start of a batch system.

## DONE

* Make 0, 0 be at top left (should vertex data be flipped, or is it a transformation thingy?)
* Construct vertex buffer from k2.draw_blabla calls. Do we need index buffer? 🤷‍
* Organize the d3d11 things neatly. It's just a hack right now!
	* enable debug layers
	* asserting on hresult and checking errors
	* clean up on shutdown