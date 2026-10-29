#!/usr/bin/env python3
"""Render a native 6912-byte Spectrum screen; requires Pillow for this utility."""
from pathlib import Path
from PIL import Image
import sys
ROOT=Path(__file__).resolve().parent.parent
s=(ROOT/(sys.argv[1] if len(sys.argv)>1 else 'build/reference.scr')).read_bytes()
im=Image.new('RGB',(256,192))
colors=[(0,0,0),(0,0,215),(215,0,0),(215,0,215),(0,215,0),(0,215,215),(215,215,0),(215,215,215)]
for y in range(192):
    for x in range(256):
        attr=s[6144+(y//8)*32+x//8]
        bits=s[(y&192)*32+(y&7)*256+(y&56)*4+x//8]
        color=colors[(attr&7) if bits & (128>>(x&7)) else ((attr>>3)&7)]
        if attr&64:color=tuple(255 if c else 0 for c in color)
        im.putpixel((x,y),color)
im.resize((1024,768),Image.Resampling.NEAREST).save(ROOT/(sys.argv[2] if len(sys.argv)>2 else 'PREVIEW.png'))
if len(sys.argv)==1:im.save(ROOT/'build/reference.png')
