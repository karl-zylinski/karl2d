___This library is NOT ready for use!___

Karl2D is a work-in-progress library for creating 2D games using the Odin Programming Language.

The API is based on Raylib because I like that API. But the implementation is meant to have as few dependencies as possible (only `core` libs and rendering APIs in `vendor`). The API will not be identical to Raylib. I'll modify to fit Odin better etc.

## What features of Raylib will not be included?

* 3D
* Some maths things that can be found in Odin's core libs

Might not be included:
* Time management (use `core:time` instead)

## TODO

Here follows my near-future TODO list

* Texture things are a bit of a hack
	* Make the sampler state configurable
	* Group set_tex, camera etc into a section of things that cause a render batch dispatch when changed.
	* Do we need the SRV in the texture?
* Do proper checks of vertex count and dispatch rendering when full
	* What happens when list is full? We can't just empty the vertex list due to being used by input assembler etc.
* Should we sort by depth? Maybe we should use Vec3 because some 2D games rely on it?


## DONE

* Make a texture for drawing a rectangle and remove the hack in `shader.hlsl`
* Load textures and somehow bind to shader -- split draw calls on texture switch -- needs a start of a batch system.
* Make 0, 0 be at top left (should vertex data be flipped, or is it a transformation thingy?)
* Construct vertex buffer from k2.draw_blabla calls. Do we need index buffer? 🤷‍
* Organize the d3d11 things neatly. It's just a hack right now!
	* enable debug layers
	* asserting on hresult and checking errors
	* clean up on shutdown
