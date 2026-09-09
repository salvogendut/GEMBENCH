"""Identical read-only chooser fixture/input scenario for both receivers."""
from pathlib import Path
import subprocess

PAYLOAD = b'Chosen through the portable file dialog.\r\n'
FEATURES = dict(UNIVERSAL_FS='1', UNIVERSAL_FILEPICK='1', UNIVERSAL_DOCIO='1',
                UNIVERSAL_WINDOW_KIND='1', APP_ICON='apps/fsprobe/icon.asm', DATA_LOC='0x6B40')


def fixture(directory):
    directory = Path(directory)
    (directory/'DIR').mkdir(parents=True)
    (directory/'EMPTY').mkdir()
    (directory/'DIR/HELLO.TXT').write_bytes(PAYLOAD)
    for i in range(10):
        (directory/f'FILE{i:02}.TXT').write_bytes(f'File {i}\n'.encode())
    (directory/'IGNORE.BIN').write_bytes(b'Not a document')


def stage_image(image, directory):
    """Explicit FAT insertion order, independent of host/readdir/mcopy recursion."""
    disk = str(image)+'@@16384'
    for name in ('DOCUI','DOCUI/DIR','DOCUI/EMPTY'):
        subprocess.run(['mmd','-i',disk,'::/'+name],check=True)
    for name in ('DIR/HELLO.TXT',*[f'FILE{i:02}.TXT' for i in range(10)],'IGNORE.BIN'):
        subprocess.run(['mcopy','-i',disk,str(Path(directory)/name),'::/DOCUI/'+name],check=True)


def status_pixels(values, font, pixel):
    """Independent glyph check: application state alone does not prove repaint."""
    y=40 if values[10] else 156
    text=('Document loaded' if values[10]==2 else 'Destination selected (no write)'
          if values[10]==3 else 'Cancelled' if values[0]==8 else
          'Select a file or folder' if values[2] else 'No matching files')
    width,height=font[7:9]
    for i,ch in enumerate(text):
        at=16+(ord(ch)-font[5])*height
        for gy in range(height):
            for gx in range(width):
                expected=2 if font[at+gy] & (128>>gx) else 1
                if pixel(24+i*width+gx,y+gy)!=expected: return False
    return True


def exercise(click, observe):
    """observe waits for expected state, checks guards/code and returns path/name.
    Coordinates belong to the same runtime-sized APP window on either target.
    All mutations are ordinary pointer input, not injected guest instructions.
    """
    checks = []

    def check(name, fields, path=None, raw=None, data=None):
        result = observe(name, fields)
        if path is not None and result['path'] != path:
            raise AssertionError(f'{name}: path {result["path"]!r} != {path!r}')
        if raw is not None and result['name'] != raw:
            raise AssertionError(f'{name}: selected name {result["name"]!r}')
        if data is not None and result['data'] != data:
            raise AssertionError(f'{name}: selected bytes differ')
        checks.append(name)

    check('chooser-root', {0:5,1:0,2:6,3:1,4:0,5:0,10:0}, '/DOCUI')
    click(26,119); check('chooser-next', {0:5,2:6,3:0,5:6})
    click(11,119); check('chooser-prev', {0:5,2:6,3:1,5:0})
    click(11,64); check('chooser-empty', {0:5,2:0,3:0}, '/DOCUI/EMPTY')
    click(39,119); check('chooser-parent', {0:5,2:6,3:1}, '/DOCUI')
    click(11,54); check('chooser-folder', {0:5,2:1,3:0}, '/DOCUI/DIR')
    click(11,54); check('chooser-readback', {0:7,4:0,8:len(PAYLOAD),9:0,10:2},
                        '/DOCUI/DIR', b'HELLO   TXT', PAYLOAD)
    click(21,4); check('chooser-save-as', {0:5,1:1,2:6,3:1,10:0}, '/DOCUI')
    click(11,74); check('chooser-save-name', {0:5,1:1,4:0,10:0})
    click(11,148); check('chooser-destination', {0:7,1:1,4:0,10:3},
                         '/DOCUI', b'FILE00  TXT')
    click(12,4); check('chooser-open-again', {0:5,1:0,2:6,10:0})
    click(55,119); check('chooser-cancel', {0:8,4:0,10:0})
    click(12,4); check('chooser-restart', {0:5,1:0,2:6,10:0})
    return checks
