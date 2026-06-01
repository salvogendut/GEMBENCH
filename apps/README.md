# apps/

Bundled GEOBENCH applications — programs that run on top of the kernel + desktop
and prove the platform is real. Loaded from disk on demand (GEOS-style); not
resident.

## Candidate first apps

- **A file manager / disk browser** — arguably part of the desktop, but a good
  first "real" app to exercise the API.
- **geoPaint-style bitmap editor** — draw, save, load.
- **geoWrite-style text editor** — proportional-font text editing.
- **A clock / system info widget** — tiny, good for testing the app lifecycle.

The point of the first app is less about the app itself and more about
validating the **application API**: load from disk, get a window, handle input,
draw, clean up, return to the desktop.

## App contract (to be specified)

Each app will be a relocatable/loadable binary that:

1. Is loaded by the kernel into an allocated memory block.
2. Receives control plus a pointer to the system API call gate.
3. Requests a window from the desktop / windowing layer.
4. Runs its event loop until the user quits.
5. Releases its resources and returns control to the desktop.

## Status

Not started. Blocked on the kernel app-loader and the windowing layer.
