# desktop/

The GEOBENCH desktop shell — the Workbench-style environment the user actually
sees and interacts with. This is the "Workbench" half of the project.

## Responsibilities

- **The desktop surface** — the backdrop on which icons and windows live.
- **Icons** — visual representations of disks, drawers (folders), and files;
  selecting, opening, and drag-and-drop.
- **Drawers** — folder windows the user can open, arrange, and browse.
- **Windows** — open / close / move / front-to-back, drawn via `lib/` windowing.
- **Menus** — the system menu bar and per-window actions.
- **Trashcan** — delete via drag-to-trash, in the Amiga spirit.
- **File manager behaviour** — copy / move / rename / delete on disk objects.

## Relationship to the rest of the system

The desktop is *an application* that runs on top of the `kernel/` and `lib/`
layers — it has no special hardware privileges beyond what the API grants. In
principle a different shell could replace it.

## Status

Not started. First milestone: draw a static desktop with a mouse pointer.
