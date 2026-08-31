# GB-BASIC

GB-BASIC is GEMBENCH's MSX2-native, GW-BASIC-flavoured BASIC. It is bundled
in-tree so the normal GEMBENCH build has no sibling-repository dependency.

It consists of:

- `BASIC.APP`, the program editor with a Run command;
- `BASRUN.APP`, the interpreter and 40×20 console; and
- `BASRUN2.BIN`, the low-RAM floating-point and graphics engine.

Programs use line numbers, Microsoft Binary Format single-precision numbers,
strings, arrays, structured loops, subroutines, keyboard input, and 240×160
four-pen graphics. See [the language reference](docs/LANGUAGE.md) for details.

## Build

From this directory:

```sh
make msx       # dist/GBBASIC-MSX.DSK
make qa-msx    # build and run the openMSX smoke test
```

The default `GEOBENCH=../..` builds against the enclosing checkout. RASM, SDCC,
`mkfs.fat`, and mtools must be available. The root distribution build invokes
`make raws-msx` and stages the three runtime files plus the example programs.

`BASRUN2.BIN` must remain beside the applications and programs because BASRUN
loads the overlay from its current directory. The shipped GEMBENCH MSX2 media
already has the correct layout.

## Runtime notes

BASRUN advances ordinary statements and graphics in bounded slices so the
desktop remains responsive. Its program, variable, and console buffers occupy
the shared low-RAM module-transfer area at `0x2200–0x3DFF`; avoid running a
simultaneous File Manager copy while a BASIC program is active.

## Provenance and license

The imported source revision and its one imported working-tree icon change are
recorded in [PROVENANCE.md](PROVENANCE.md). This component is distributed under
GEMBENCH's BSD 3-Clause license; see [LICENSE](LICENSE).
