// Glueing the Windows window to the D3D11 backend is very simple: We just need to return the window
// handle. Since D3D11 only work on windows-like systems, we do not need to do any "context setup"
// in here, the D3D11 backend knows that it is getting a HWND handle.
//
// This whole interface is _overkill_ for Windows. We just use it as thing to hold a window handle.
// But we need to conform to it due to the `Render_Backend_Interface` being platform/windowing
// agnostic.
#+build windows
#+private file
package karl2d

import win32 "core:sys/windows"

@(private="package")
make_windows_d3d11_glue :: proc(hwnd: win32.HWND) -> Window_Render_Glue {
	return {
		state = (^Window_Render_Glue_State)(hwnd),
		get_window_handle = wdg_get_window_handle,
	}
}

// wdg == WindowsD3D11Glue
wdg_get_window_handle :: proc(state: ^Window_Render_Glue_State) -> Window_Handle {
	return Window_Handle(state)
}