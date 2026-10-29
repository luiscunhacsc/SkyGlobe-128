#!/usr/bin/env python3
"""Build a real, banked ZX Spectrum 128 TAP. Python 3 + pyz80 + astronomy-engine.
Data generation is deterministic and entirely offline when data/ is populated.
"""
from pathlib import Path
import csv, datetime as dt, hashlib, json, math, shutil, struct, subprocess, sys

ROOT = Path(__file__).resolve().parent.parent
DATA, BUILD, SRC = ROOT/'data', ROOT/'build', ROOT/'source'
BUILD.mkdir(exist_ok=True)
def read(name): return json.loads((DATA/name).read_text())
def vec(lon, lat):
    a, d = math.radians(lon), math.radians(lat)
    return [round(127*math.cos(d)*math.cos(a)), round(127*math.cos(d)*math.sin(a)), round(127*math.sin(d))]
def bvec(v): return bytes(x & 255 for x in v)
def ascii_name(s):
    import unicodedata
    return unicodedata.normalize('NFKD',s).encode('ascii','ignore').decode().upper().replace('  ',' ')[:22]
def db(data): return '\n'.join(' DB '+','.join(str(x) for x in data[i:i+24]) for i in range(0,len(data),24))+'\n'
def block(flag, data):
    raw=bytes([flag])+bytes(data)
    check=0
    for x in raw: check ^= x
    return struct.pack('<H',len(raw)+1)+raw+bytes([check])
def named_block(name, data, address=49152, kind=3, p2=32768):
    header=bytes([kind])+name.encode('ascii')[:10].ljust(10,b' ')+struct.pack('<HHH',len(data),address,p2)
    return block(0,header)+block(255,data)

def generate():
    stars=sorted(read('stars.6.json')['features'],key=lambda s:(s['properties']['mag'],int(s['id'])))
    starbytes=bytearray()
    for s in stars:
        starbytes += bvec(vec(*s['geometry']['coordinates']))+bytes([max(0,round(10*s['properties']['mag'])+20)])
    bank0=starbytes[:16384]
    bank1=bytearray(starbytes[16384:])
    constants={'STAR0_COUNT':4096,'STAR1_COUNT':len(stars)-4096,'STAR_TOTAL':len(stars)}
    def section(name, data, count=None):
        constants[name+'_ADDR']=49152+len(bank1)
        if count is not None: constants[name+'_COUNT']=count
        bank1.extend(data)

    # Paths retain all original vertices. A flag begins each separate stroke.
    lines=bytearray(); nlines=0
    for f in read('constellations.lines.json')['features']:
        for path in f['geometry']['coordinates']:
            for i,p in enumerate(path):
                lines.extend(bvec(vec(*p))+bytes([0 if i==0 else 1])); nlines+=1
    section('LINES',lines,nlines)

    # Sample the published Milky Way outline into native 8x8 attribute patches.
    # Unwrap each polygon at the 180-degree seam before point-in-polygon.
    # Work in galactic coordinates to avoid treating a spherical polygon
    # crossing the RA seam as a flat polygon. Bin the actual outer contour.
    rot=[[-.0548755604,-.8734370902,-.4838350155],
         [.4941094279,-.4448296300,.7469822445],
         [-.8676661490,-.1980763734,.4559837762]]
    contour=[]
    for poly in read('mw.json')['features'][0]['geometry']['coordinates']:
        for ring in poly:
            for ra,dec in ring:
                a,d=map(math.radians,[ra,dec]);v=[math.cos(d)*math.cos(a),math.cos(d)*math.sin(a),math.sin(d)]
                g=[sum(a*b for a,b in zip(row,v)) for row in rot]
                contour.append((math.degrees(math.atan2(g[1],g[0]))%360,math.degrees(math.asin(g[2]))))
    milky=[]
    for lon in range(0,360,3):
        bounds=[b for l,b in contour if abs((l-lon+180)%360-180)<=3]
        if not bounds: continue
        lo,hi=min(bounds),max(bounds)
        for lat in range(math.ceil(lo/3)*3,math.floor(hi/3)*3+1,3):
            l,b=map(math.radians,[lon,lat]);g=[math.cos(b)*math.cos(l),math.cos(b)*math.sin(l),math.sin(b)]
            milky.append([round(127*sum(rot[j][i]*g[j] for j in range(3))) for i in range(3)])
    section('MILKY',b''.join(bvec(v) for v in milky),len(milky))

    # Search records: kind / XYZ / display label (NUL) / searchable name (NUL).
    # The same records drive the labels, finder, and selection information.
    names=read('starnames.json'); objects=[]
    for s in stars:
        n=names.get(str(s['id']),{}).get('name','')
        if n and (s['properties']['mag']<=2.3 or n in ['Polaris','Alcor','Albireo']):
            objects.append((0,vec(*s['geometry']['coordinates']),ascii_name(n)[:13],ascii_name(n)))
    star_obj_count=len(objects)
    for f in read('constellations.json')['features']:
        ra,dec=f['geometry']['coordinates']
        objects.append((1,vec(ra,dec),f['id'].upper(),ascii_name(f['properties']['name'])))
    for f in read('messier.json')['features']:
        short=f['id']; alt=ascii_name(f['properties'].get('alt',''))
        full=(short+' '+alt).strip()[:22]
        objects.append((2,vec(*f['geometry']['coordinates']),short,full))
    planets=['SUN','MOON','MERCURY','VENUS','MARS','JUPITER','SATURN','URANUS','NEPTUNE']
    for i,n in enumerate(planets): objects.append((3,[i,0,0],n,n))
    objbytes=bytearray(); obj_offsets=[]
    for kind,v,label,name in objects:
        obj_offsets.append(49152+len(bank1)+len(objbytes))
        objbytes+=bytes([kind])+bvec(v)+label.encode()+b'\0'+name.encode()+b'\0'
    section('OBJECTS',objbytes,len(objects))
    constants['STAR_OBJECT_COUNT']=star_obj_count
    section('OBJ_PTRS',b''.join(struct.pack('<H',o) for o in obj_offsets),len(objects))
    if len(bank1)>16384: raise RuntimeError(f'Bank 1 overflows: {len(bank1)}')
    (BUILD/'bank0.bin').write_bytes(bank0.ljust(16384,b'\0'))
    (BUILD/'bank1.bin').write_bytes(bank1.ljust(16384,b'\0'))

    # Astronomy Engine GeoVector returns geocentric J2000 equatorial vectors.
    # Daily samples are linearly interpolated by the native program, including
    # the Moon; do not substitute a single frozen position for a whole day.
    import astronomy
    bodies=[astronomy.Body.Sun,astronomy.Body.Moon,astronomy.Body.Mercury,astronomy.Body.Venus,
            astronomy.Body.Mars,astronomy.Body.Jupiter,astronomy.Body.Saturn,astronomy.Body.Uranus,astronomy.Body.Neptune]
    ephem=bytearray(); lunar=bytearray(); day=dt.date(2025,1,1)
    lunar_radii=[]
    for k in range(1462):
        d=day+dt.timedelta(days=k)
        t=astronomy.Time.Parse(d.isoformat()+'T00:00:00Z')
        daily=[]
        for body in bodies:
            v=astronomy.GeoVector(body,t,True); length=math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
            ephem+=bvec([round(c/length*127) for c in [v.x,v.y,v.z]])
            daily.append((v,length))
        sun,_=daily[0]; moon,moon_dist=daily[1]
        light=[sun.x-moon.x,sun.y-moon.y,sun.z-moon.z]
        light_length=math.sqrt(sum(c*c for c in light))
        light=[c/light_length for c in light]
        phase_cos=-sum(a*b for a,b in zip(light,[moon.x,moon.y,moon.z]))/moon_dist
        # Mean physical lunar radius: 1737.4 km. Store angular SEMI-diameter
        # in radians * 65536; illumination is actual Sun-Moon-Earth geometry.
        radius=round(math.asin(1737.4/(moon_dist*astronomy.KM_PER_AU))*65536)
        lunar_radii.append(radius)
        lunar+=bvec([round(c*127) for c in light])+bytes([round(phase_cos*127)&255])+struct.pack('<H',radius)
    constants['LUNAR_ADDR']=49152+len(ephem)-32768
    constants['LUNAR_RECORD_SIZE']=6
    assert len(ephem)-32768+len(lunar)<=16384, 'Lunar ephemeris exceeds bank 6'
    (BUILD/'lunar.bin').write_bytes(lunar)
    for i,bank in enumerate([3,4,6]):
        data=ephem[i*16384:(i+1)*16384]
        if bank==6:data+=lunar
        (BUILD/f'bank{bank}.bin').write_bytes(data.ljust(16384,b'\0'))

    # 3x5 glyphs, with one pixel of letter and line spacing: 64 columns.
    font={
      ' ':['000']*5, '!':['010','010','010','000','010'], '?':['110','001','010','000','010'],
      '"':['101','101','000','000','000'], '#':['101','111','101','111','101'],
      '+':['000','010','111','010','000'], '-':['000','000','111','000','000'],
      '.':['000','000','000','000','010'], ',':['000','000','000','010','100'],
      ':':['000','010','000','010','000'], '/':['001','001','010','100','100'],
      '=':['000','111','000','111','000'], '*':['000','101','010','101','000'],
      '(' :['010','100','100','100','010'], ')':['010','001','001','001','010'],
      '<':['001','010','100','010','001'], '>':['100','010','001','010','100'],
      '0':['111','101','101','101','111'], '1':['010','110','010','010','111'],
      '2':['110','001','010','100','111'], '3':['110','001','010','001','110'],
      '4':['101','101','111','001','001'], '5':['111','100','110','001','110'],
      '6':['011','100','111','101','111'], '7':['111','001','010','010','010'],
      '8':['111','101','111','101','111'], '9':['111','101','111','001','110'],
      'A':['010','101','111','101','101'], 'B':['110','101','110','101','110'],
      'C':['011','100','100','100','011'], 'D':['110','101','101','101','110'],
      'E':['111','100','110','100','111'], 'F':['111','100','110','100','100'],
      'G':['011','100','101','101','011'], 'H':['101','101','111','101','101'],
      'I':['111','010','010','010','111'], 'J':['001','001','001','101','010'],
      'K':['101','101','110','101','101'], 'L':['100','100','100','100','111'],
      'M':['101','111','111','101','101'], 'N':['101','111','111','111','101'],
      'O':['010','101','101','101','010'], 'P':['110','101','110','100','100'],
      'Q':['010','101','101','111','011'], 'R':['110','101','110','101','101'],
      'S':['011','100','010','001','110'], 'T':['111','010','010','010','010'],
      'U':['101','101','101','101','111'], 'V':['101','101','101','101','010'],
      'W':['101','101','111','111','101'], 'X':['101','101','010','101','101'],
      'Y':['101','101','010','010','010'], 'Z':['111','001','010','100','111'],
      '[':['110','100','100','100','110'], ']':['011','001','001','001','011'],
      '_':['000','000','000','000','111']}
    fontbin=bytes(int(row,2)<<1 for c in range(32,96) for row in font.get(chr(c),font['?']))
    sine=bytes(round(127*math.sin(i*math.tau/1024))&255 for i in range(1024))
    # Horizon sampled in the local frame; converted with the same view matrix.
    horizon=b''.join(bvec(vec(a,0)) for a in range(0,361,3))
    equator=b''.join(bvec(vec(a,0)) for a in range(0,361,3))
    eps=math.radians(23.4393)
    ecliptic=b''.join(bvec([round(127*math.cos(math.radians(a))),round(127*math.sin(math.radians(a))*math.cos(eps)),round(127*math.sin(math.radians(a))*math.sin(eps))]) for a in range(0,361,3))
    inc='; Generated by build.py. All addresses are native Z80 addresses.\n'
    inc+='\n'.join(f'{k}: EQU {v}' for k,v in constants.items())+'\n'
    inc+='font_data:\n'+db(fontbin)+'sine_data:\n'+db(sine)
    inc+='equator_points:\n'+db(equator)+'ecliptic_points:\n'+db(ecliptic)
    inc+='moon_squares:\n'+db(b''.join(struct.pack('<H',i*i) for i in range(64)))
    (SRC/'generated.inc').write_text(inc)
    manifest={'stars':len(stars),'constellations':88,'constellation_paths':len(lines)//4,
       'milky_way_samples':len(milky),'search_objects':len(objects),'bank1_bytes':len(bank1),
       'ephemeris_days':1462,'ephemeris_first':'2025-01-01','ephemeris_last':'2029-01-01',
       'lunar_record_bytes':6,'lunar_radius_km':1737.4,
       'lunar_angular_radius_q16_range':[min(lunar_radii),max(lunar_radii)],
       'sources':{f:hashlib.sha256((DATA/f).read_bytes()).hexdigest() for f in ['stars.6.json','constellations.lines.json','constellations.json','starnames.json','mw.json','messier.json']}}
    (BUILD/'catalogue.json').write_text(json.dumps(manifest,indent=2))
    print(json.dumps(manifest,indent=2))

def main():
    if '--assemble-only' not in sys.argv: generate()
    for unit in ['skyglobe','loader']:
        subprocess.run([sys.executable,'-m','pyz80.pyz80',f'--obj={BUILD/unit}.bin',f'--mapfile={BUILD/unit}.map',
             f'--exportfile={BUILD/unit}.symbols',str(SRC/f'{unit}.asm')],check=True,cwd=ROOT)
    # Native bank loader calls the Spectrum ROM LD-BYTES for every header/data
    # pair; no JavaScript assistance is used for program logic or rendering.
    loader=(BUILD/'loader.bin').read_bytes(); code=(BUILD/'skyglobe.bin').read_bytes()
    # Spectrum BASIC: CLEAR 24575: LOAD "" CODE: RANDOMIZE USR 24000
    line=bytes([0xFD])+b'24575'+bytes([0x0e,0,0,0xff,0x5f,0])+b':'+bytes([0xEF])+b'"" '+bytes([0xAF])+b':'+bytes([0xF9,0xC0])+b'24000'+bytes([0x0e,0,0,0xc0,0x5d,0,0x0d])
    basic=struct.pack('>H',10)+struct.pack('<H',len(line))+line
    tap=named_block('SKYGLOBE',basic,10,0,len(basic))+named_block('BOOT128',loader,24000)
    tap+=named_block('SKY128',code,24576)
    for bank in [0,1,3,4,6]: tap+=named_block(f'SKYBANK{bank}',(BUILD/f'bank{bank}.bin').read_bytes())
    (ROOT/'SKYGLOBE128.tap').write_bytes(tap)
    print('TAP:',len(tap),'bytes; code:',len(code),'bytes; loader:',len(loader),'bytes')
    if (ROOT/'developer').exists():
        shutil.copy2(ROOT/'SKYGLOBE128.tap',ROOT/'developer/TAPs/SKYGLOBE128.tap')
        subprocess.run([sys.executable,str(ROOT/'developer/build_single_html.py')],check=True)

if __name__=='__main__':main()
