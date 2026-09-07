# Window title-bar gadgets

`.GDT` files contain the two reusable window-title gadgets in canonical
four-pen CPC Mode-1 packing: an 8x10 close tile (20 bytes), followed by a 12x10
maximize tile (30 bytes). Each file is therefore exactly 50 bytes and is shared
unchanged by the MSX distribution and experimental CPC runtime; no new
platform-specific gadget format is introduced for the future PCW port.

Edit a gadget pair alongside any title motif with:

```sh
python3 tools/titlebaredit.py assets/titlebars/ORIGINAL.TBR assets/gadgets/ORIGINAL.GDT
```

The editor previews the selected `.TBR` and `.GDT` together but saves them
independently. MSX Settings exposes the same separation through **Title bar** and
**Gadgets**, backed by:

```ini
TITLEBAR=ORIGINAL
GADGETS=ORIGINAL
```

The MSX distribution and private CPC M4 runtime carry every gadget theme.
CPC Settings/full Desktop and the PCW port remain pending; see the
[CPC chrome checkpoint](../../docs/CPC-RESTART-STEP3D-U.md).
The tracked catalogue currently has two unique pairs: `ORIGINAL.GDT` and
`IMPROVED.GDT`; the other former combined title themes used ORIGINAL gadgets.
