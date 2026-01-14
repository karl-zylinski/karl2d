// Glueing the Windows window to the D3D11 backend is very simple: We just need to return the window
// handle. Since D3D11 only work on windows-like systems, we do not need to do any "context setup"
// in here, the D3D11 backend knows that it is getting a HWND handle.
//
// This whole interface is _overkill_ for Windows. We just use it as thing to hold a window handle.
// See `platform_windows_glue_gl.odin` for a more comprehensive example.
#+build windows
#+private file
package karl2d

import win32 "core:sys/windows"

@(private="package")
make_windows_d3d11_glue :: proc(hwnd: win32.HWND) -> Window_Render_Glue {
	return {
		state = (^Window_Render_Glue_State)(hwnd),
	}
}
