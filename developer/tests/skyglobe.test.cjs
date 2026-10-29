const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {test}=require('node:test');
const {root,symbols,byte,word,put,putw,wait,key,screen,start,call}=require('./skyglobe-harness.cjs');

test('SkyGlobe loads its native TAP via the 128K ROM and draws the reference sky',async()=>{
 const e=await start();
 assert.equal(e.evaluate('tapeIndex'),e.evaluate('tapeBuffer.byteLength'));
 assert.equal(e.evaluate('machineModel'),'128K');
 assert.equal(e.evaluate('pagingLatch & 8'),8);
 assert.equal(word(e,'day_index'),82);
 assert.equal(word(e,'azimuth'),32768);
 assert.equal(word(e,'elevation'),8192);
 assert.ok(word(e,'shown_stars')>2800);
 const scr=screen(e);assert.ok(scr.subarray(0,6144).filter(x=>x).length>1500);
 assert.ok(scr.subarray(6144).some(a=>(a&56)===8),'Native blue-paper Milky Way');
 fs.writeFileSync(path.join(root,'build/reference.scr'),scr);
});

test('navigation, all 5044 stars, zoom, layers, location and reverse adjustments execute on Z80',async()=>{
 const e=await start();const original=screen(e);
 key(e,'KeyB');assert.equal(word(e,'shown_stars'),5044,'Both star RAM banks must be read');
 key(e,'KeyB','ControlLeft');assert.equal(byte(e,'mag_limit'),75);
 key(e,'ArrowRight');assert.equal(word(e,'azimuth'),32768+910);
 key(e,'KeyZ');assert.equal(byte(e,'zoom_index'),3);assert.notDeepEqual(screen(e),original);
 for(const [code,state] of [['KeyC','lines_on'],['KeyK','milky_on'],['KeyG','grid_on'],['KeyU','dso_on'],['KeyP','planets_on'],['KeyX','mirror_on']]){
   const before=byte(e,state);key(e,code);assert.equal(byte(e,state),before^1);
 }
 key(e,'KeyL');assert.equal(byte(e,'location_index'),1);assert.equal(word(e,'longitude'),64005);
 const m=word(e,'minutes');key(e,'KeyH');assert.equal(word(e,'minutes'),m+60);
 key(e,'KeyH','ControlLeft');assert.equal(word(e,'minutes'),m);
 key(e,'Digit0');assert.equal(word(e,'azimuth'),32768);assert.equal(word(e,'minutes'),642);
});

test('finder accepts typed names and centres a real catalogue star',async()=>{
 const e=await start();e.key('KeyF');wait(e,'finder_wait');
 for(const code of ['KeyV','KeyE','KeyG','KeyA']){e.key(code);wait(e,'finder_wait');}
 assert.equal(byte(e,'result_count'),1);
 e.key('Enter');wait(e);
 assert.ok(word(e,'selected_ptr')>=49152);
 assert.ok(word(e,'azimuth')!==32768);
 // Independently check Vega is within a few pixels of the screen centre.
 e.evaluate(`writeMemory(${symbols.temp_vec},24);writeMemory(${symbols.temp_vec+1},143);writeMemory(${symbols.temp_vec+2},80)`);
 const vega=JSON.parse(fs.readFileSync(path.join(root,'data/stars.6.json'),'utf8')).features.find(f=>f.id===91262);
 const [ra,dec]=vega.geometry.coordinates.map(a=>a*Math.PI/180);
 const v=[Math.round(127*Math.cos(dec)*Math.cos(ra)),Math.round(127*Math.cos(dec)*Math.sin(ra)),Math.round(127*Math.sin(dec))];
 for(let i=0;i<3;i++)e.evaluate(`writeMemory(${symbols.temp_vec+i},${v[i]&255})`);
 const s=call(e,'project',{ix:symbols.temp_vec});
 assert.equal(s.flags.C,0);assert.ok(Math.abs(byte(e,'px')-128)<=4);assert.ok(Math.abs(byte(e,'py')-96)<=4,JSON.stringify({x:byte(e,'px'),y:byte(e,'py'),az:word(e,'azimuth'),el:word(e,'elevation'),local:e.evaluate(`Array.from({length:3},(_,i)=>readMemory(${symbols.local_vec}+i))`)}));
});

test('a brief key press during a redraw is retained by the native interrupt',async()=>{
 const e=await start();
 e.key('KeyZ');
 e.key('KeyC',1);
 wait(e);e.frames(20);wait(e);
 assert.equal(byte(e,'lines_on'),0);
});

test('calendar handles leap day, reverse midnight, and both ephemeris bank boundaries',async()=>{
 const e=await start();
 put(e,'year',3);put(e,'month',2);put(e,'day',28);putw(e,'minutes',1439);
 key(e,'KeyT');assert.equal(byte(e,'day'),29);assert.equal(word(e,'minutes'),0);
 key(e,'KeyT','ControlLeft');assert.equal(byte(e,'day'),28);assert.equal(word(e,'minutes'),1439);
 const ephem=Buffer.concat([3,4,6].map(n=>fs.readFileSync(path.join(root,`build/bank${n}.bin`))));
 for(const index of [606,1213,1460]){
   const date=new Date(Date.UTC(2025,0,1)+index*86400000);
   put(e,'year',date.getUTCFullYear()-2025);put(e,'month',date.getUTCMonth()+1);put(e,'day',date.getUTCDate());putw(e,'minutes',0);
   key(e,'KeyT');assert.equal(word(e,'day_index'),index);
   const samples=Buffer.from(e.evaluate(`Array.from({length:54},(_,i)=>readMemory(${symbols.planet_samples}+i))`));
   assert.deepEqual(samples,ephem.subarray(index*27,index*27+54));
 }
});

test('native fixed point projection agrees with independent spherical geometry',async()=>{
 const e=await start();const rad=Math.PI/180;
 for(const [loc,lat,lon] of [[0,42.75,-85.5],[1,40.2033,-8.4103],[4,-33.8688,151.2093]]){
   if(loc!==byte(e,'location_index')){put(e,'location_index',(loc+5)%6);put(e,'reverse',0);call(e,'change_location');}
   for(const [az,el] of [[0,20],[90,45],[180,45],[270,-15]]){
     putw(e,'azimuth',Math.round(az*65536/360));putw(e,'elevation',Math.round(el*65536/360)&65535);
     call(e,'make_matrix');call(e,'make_tables');
     const lst=word(e,'lst_phase')*2*Math.PI/65536;
     const U=[Math.cos(lat*rad)*Math.cos(lst),Math.cos(lat*rad)*Math.sin(lst),Math.sin(lat*rad)];
     const N=[-Math.sin(lat*rad)*Math.cos(lst),-Math.sin(lat*rad)*Math.sin(lst),Math.cos(lat*rad)];
     const E=[-Math.sin(lst),Math.cos(lst),0];
     const H=N.map((v,i)=>v*Math.cos(az*rad)+E[i]*Math.sin(az*rad));
     const F=H.map((v,i)=>v*Math.cos(el*rad)+U[i]*Math.sin(el*rad));
     const R=N.map((v,i)=>-v*Math.sin(az*rad)+E[i]*Math.cos(az*rad));
     const V=U.map((v,i)=>v*Math.cos(el*rad)-H[i]*Math.sin(el*rad));
     for(const [dx,dy] of [[0,0],[25,20],[-30,10],[10,-25]]){
       let p=F.map((v,i)=>v+R[i]*Math.tan(dx*rad)+V[i]*Math.tan(dy*rad));const len=Math.hypot(...p);p=p.map(v=>v/len);
       const v=p.map(v=>Math.round(v*127));for(let i=0;i<3;i++)e.evaluate(`writeMemory(${symbols.temp_vec+i},${v[i]&255})`);
       const s=call(e,'project',{ix:symbols.temp_vec});assert.equal(s.flags.C,0);
       const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
       const x=128+224*dot(p,R)/(1+dot(p,F)),y=96-224*dot(p,V)/(1+dot(p,F));
       assert.ok(Math.abs(byte(e,'px')-x)<5,`${loc}/${az}/${el}: x ${byte(e,'px')} vs ${x}`);
       assert.ok(Math.abs(byte(e,'py')-y)<5,`${loc}/${az}/${el}: y ${byte(e,'py')} vs ${y}`);
     }
   }
 }
});
