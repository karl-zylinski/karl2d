## TODO

High-level TODO before beta release:
x Complete JS window impl
X Fix render target drawing on gl and webgl
/ Make text rendering look good
	- its better now, but I think I need to rewrite fontstash (my own "fontcache" or something)
X Figure out what to do with the delta time stuff, built in or separate?
- make a good color palette
- Look into webgl performance (bunnymark)
- Understand texture format choices in webgl and gl backend and fix anything that is wrong


Things to get feedback on:
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




* Can we reuse memory for const buffers and union blocks between shaders? Just create reasonably sized ones and fetch based on size or something.
* should gamepad come from separate interface than window?
	* keyboard input could also come from some input interface, but
	  it is tightly bound to window in windows, so we'll see.
* add more window flags
* win32: Gamepad support
	x check status of gamepad
	x what happens when you pull one out?
	* playstation
* Textures: Make the sampler state configurable
	x filtering (still needs to fix GL)
	* wrapping

* mipmap support
	* try gl first, seems easier
	* fix gl filtering filtering setting for mips

* render textures
	x d3d
	x gl
* do pixel-perfect rendering tests: render texture with 1:1 pixel matching etc
* linux windowing and input
x webgl backend
x should we expose time and delta time stuff or rely on core:time?
* think about sound
* add shapes drawing texture override

## DONE
* set filtering: for scaling up, down and mipmap
* Shaders: Reflect and expose samplers
	* generalised sampler handling for both gl and d3d
* GL backend:
	textures --- try make the d3d11 backend support multiple textures first and
	             then generalize to gl

	             for d3d11: we need to reflect bound resources for both vs and ps... if they are
	             shared then perhaps we only need one buffer -- also, should you create less buffers
	             and reuse them between shaders? So it doesn't become lots of buffers for each shader
	             permutation
	X set uniforms -- needs more type info?
	X the constant types are hardcoded to just a few types right now

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
