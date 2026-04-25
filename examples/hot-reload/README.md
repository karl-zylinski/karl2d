# Hot reload for Karl2D

How to use:
- `odin run .` in same folder as `build.odin` compiles executable and game DLL
- run `bin\hot_reload\game_hot_reload.exe` (or .bin on linux/mac). Currently you execute the command the same folder as `build.odin`.
- While game is running, modify something in `game/app.odin` and run `odin run .` in same folder as `build.odin` again -- the game DLL will be recompiled and reloaded.