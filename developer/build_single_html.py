#!/usr/bin/env python3
"""Cross-platform equivalent of build_single_html.ps1; standard library only."""
from pathlib import Path
import base64,json,zipfile
ROOT=Path(__file__).resolve().parent
def b64(data):return base64.b64encode(data).decode('ascii')
def build():
    html=(ROOT/'js_spectrum.html').read_text()
    html=html.replace('<script src="Z80.js"></script>','<script>\n'+(ROOT/'Z80.js').read_text()+'\n</script>')
    for name,mime in [('keyboard.jpg','image/jpeg'),('assets/spectrum-48k.png','image/png'),('assets/spectrum-128k.png','image/png')]:
        html=html.replace('src="'+name+'"','src="data:'+mime+';base64,'+b64((ROOT/name).read_bytes())+'"')
    roms={'48K':b64((ROOT/'48.rom').read_bytes())}
    for archive in sorted((ROOT/'ZX Spectrum 128').glob('*.zip')):
        with zipfile.ZipFile(archive) as z:
            for name in z.namelist():
                if name.lower().endswith('.rom'):roms[Path(name).name]=b64(z.read(name))
    taps={'TAPs/'+p.name:b64(p.read_bytes()) for p in sorted((ROOT/'TAPs').glob('*.tap'))}
    html=html.replace('const EMBEDDED_ROM_BASE64 = {};','const EMBEDDED_ROM_BASE64 = '+json.dumps(roms,separators=(',',':'))+';')
    html=html.replace('const EMBEDDED_TAP_BASE64 = {};','const EMBEDDED_TAP_BASE64 = '+json.dumps(taps,separators=(',',':'))+';')
    (ROOT.parent/'index.html').write_text(html)
    print('Standalone emulator rebuilt:',ROOT.parent/'index.html')
if __name__=='__main__':build()
