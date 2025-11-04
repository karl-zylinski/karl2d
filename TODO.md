## TODO
* GL backend:
	textures
	set uniforms -- needs more type info?
	the constant types are hardcoded to just a few types right now

* should gamepad come from separate interface than window?
	* keyboard input could also come from some input interface, but
	  it is tightly bound to window in windows, so we'll see.
* add more window flags
* win32: Gamepad support
	* check status of gamepad
	* what happens when you pull one out?
	* playstation
* Textures: Make the sampler state configurable
* Textures D3D11: Do we need the SRV in the texture?
* Shaders: Reflect and expose samplers
	* generalised sampler handling for both gl and d3d
* mipmap support
* set filtering: for scaling up, down and mipmap
* render textures
* do pixel-perfect rendering tests: render texture with 1:1 pixel matching etc
* linux windowing and input
* webgl backend
* should we expose time and delta time stuff or rely on core:time?
* think about sound

## DONE
* Should we sort by depth? Maybe we should use Vec3 because some 2D games rely on it?
	* I think we should.
* Do proper checks of vertex count and dispatch rendering when full
	* What happens when list is full? We can't just empty the vertex list due to being used by input assembler etc.
* basic text rendering (ended up using font stash)
	* make draw_text and load_default_font do somethig more sensible
	* look at how to properly get the scale from stb_ttf
	* compare if we are doing the same as raylib by loading its default font and drawing some things, can we make it look similar?
	* font smoothing -> make it look crisp by disabling filtering on "pixel fonts"
	* next stage: Look into something more fancy than just loading bitmaps. What can we do?
* bunnymark
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
