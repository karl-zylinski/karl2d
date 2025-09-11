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

* should gamepad come from separate interface than window?
	* keyboard input could also come from some input interface, but
	  it is tightly bound to window in windows, so we'll see.
* add more window flags
* get_camera_view_matrix returns Mat4... should we go hardcore 2D and return Mat3 so you can do
    mat * Vec3{pos.x, pos.y, 1} for positions and mat * Vec3{dir.x, dir.y, 0} for dirs?
* win32: Gamepad support
	* axes
	* check status of gamepad
	* what happens when you pull one out?
* basic text rendering
* Do proper checks of vertex count and dispatch rendering when full
	* What happens when list is full? We can't just empty the vertex list due to being used by input assembler etc.
* Should we sort by depth? Maybe we should use Vec3 because some 2D games rely on it?
	* I think we should.
* Textures: Make the sampler state configurable
* Textures D3D11: Do we need the SRV in the texture?
* Shaders: Reflect and expose samplers

## DONE
* win32: Resizable window
* Flashing textures in Abyss -- Better now but still flashes when you use nose... Check the "odd_frame" stuff in d3d backend
* Is the 1/zoom in set_camera wrong? Is the matrix multiply order wrong? Hmmmm...
* Fix the depedency on D3D stuff so we can move load_shader etc
* Shaders: Basic loading
* Shaders: Constants that you can set
* Shaders: Dynamic vertex creation
* Shaders: Feed extra vertex field values using some kind of context
	* Do we need one for all corners of a rect or possibilty to supply different value for the different corners?
* Group set_tex, camera etc into a section of things that cause a render batch dispatch when changed.
* Make a texture for drawing a rectangle and remove the hack in `shader.hlsl`
* Load textures and somehow bind to shader -- split draw calls on texture switch -- needs a start of a batch system.
* Make 0, 0 be at top left (should vertex data be flipped, or is it a transformation thingy?)
* Construct vertex buffer from k2.draw_blabla calls. Do we need index buffer? 🤷‍
* Organize the d3d11 things neatly. It's just a hack right now!
	* enable debug layers
	* asserting on hresult and checking errors
	* clean up on shutdown
