# Window title-bar gadgets

`.GDT` files contain the two reusable window-title gadgets in canonical
four-pen CPC Mode-1 packing: an 8x10 close tile (20 bytes), followed by a 12x10
maximize tile (30 bytes). Each file is therefore exactly 50 bytes and is shared
unchanged by CPC, MSX, and PCW.

Edit a gadget pair alongside any title motif with:

```sh
python3 tools/titlebaredit.py assets/titlebars/ORIGINAL.TBR assets/gadgets/ORIGINAL.GDT
```

The editor previews the selected `.TBR` and `.GDT` together but saves them
independently. Settings exposes the same separation through **Title bar** and
**Gadgets**, backed by:

```ini
TITLEBAR=ORIGINAL
GADGETS=ORIGINAL
```

Card and MSX distributions carry every gadget theme. Tight CPC and PCW boot
floppies carry `ORIGINAL.GDT`; the remaining pairs are on `EXTRAS.DSK`.
The tracked catalogue currently has two unique pairs: `ORIGINAL.GDT` and
`IMPROVED.GDT`; the other former combined title themes used ORIGINAL gadgets.
