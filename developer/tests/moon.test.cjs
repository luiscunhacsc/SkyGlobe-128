const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {test}=require('node:test');
const {root,symbols,byte,word,put,putw,wait,key,start,call}=require('./skyglobe-harness.cjs');
const fixtures=require('./moon-fixtures.json');
const signed=n=>n<128?n:n-256;
const dot=(a,b)=>a.reduce((s,x,i)=>s+x*b[i],0);
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const norm=a=>{const l=Math.hypot(...a);return a.map(x=>x/l);};
function setDate(e,utc){
 const d=new Date(utc);put(e,'year',d.getUTCFullYear()-2025);put(e,'month',d.getUTCMonth()+1);put(e,'day',d.getUTCDate());
 putw(e,'minutes',d.getUTCHours()*60+d.getUTCMinutes());call(e,'calc_date_index');call(e,'load_ephemeris');
}
function bitmap(e){return Buffer.from(e.evaluate('Array.from(ramBanks[5].slice(0,6144))'));}
function pixel(s,x,y){return (s[(y&192)*32+(y&7)*256+(y&56)*4+(x>>3)]>>(7-(x&7)))&1;}
function disc(e,light,d=32,x=128,y=96){
 call(e,'clear_screen');put(e,'px',x);put(e,'py',y);put(e,'moon_diameter',d);
 for(let i=0;i<3;i++)put(e,['moon_light_r','moon_light_d','moon_light_z'][i],light[i]);
 call(e,'moon_raster');return bitmap(e);
}
function count(s){let n=0;for(let y=0;y<192;y++)for(let x=0;x<256;x++)n+=pixel(s,x,y);return n;}

test('eight real phase dates and lunar angular sizes agree with Astronomy Engine',async()=>{
 const e=await start();
 for(const f of fixtures){
  setDate(e,f.utc);
  const illuminated=(1+signed(byte(e,'lunar_phase_cos'))/127)/2;
  assert.ok(Math.abs(illuminated-f.fraction)<0.015,`${f.phase}: ${illuminated} vs ${f.fraction}`);
  assert.ok(Math.abs(word(e,'lunar_radius')/65536-f.radius_radians)<0.000025);
 }
});

test('Moon diameter follows angular scale, distance, projection and all nine zoom levels',async()=>{
 const e=await start();const radius=300/65536;
 putw(e,'lunar_radius',300);put(e,'moon_projection_den',126);
 const levels=[[96,0],[144,0],[224,0],[168,1],[224,1],[224,2],[224,3],[224,4],[224,5]];
 const sizes=[];
 for(const [scale,shift] of levels){
  put(e,'scale',scale);put(e,'zoom_shift',shift);call(e,'moon_size');
  const size=byte(e,'moon_diameter'),expected=scale*2**shift*radius;
  assert.ok(Math.abs(size-expected)<=0.55,`${scale}/${shift}: ${size} vs ${expected}`);sizes.push(size);
 }
 assert.equal(sizes[2],1,'General sky view must not use an enlarged Moon icon');
 assert.ok(sizes.at(-1)>=32);
 putw(e,'lunar_radius',280);call(e,'moon_size');const apogee=byte(e,'moon_diameter');
 putw(e,'lunar_radius',319);call(e,'moon_size');assert.ok(byte(e,'moon_diameter')>apogee);
 putw(e,'lunar_radius',300);put(e,'moon_projection_den',107);call(e,'moon_size');
 const expected=2*224*32*radius/(1+Math.cos(Math.PI/4));
 assert.ok(Math.abs(byte(e,'moon_diameter')-expected)<1);
});

test('native spherical raster draws new, quarter, crescent, gibbous and full phases',async()=>{
 const e=await start();
 const full=disc(e,[0,0,127]);const area=count(full);assert.ok(area>760&&area<860);
 assert.equal(count(disc(e,[0,0,-127])),0,'New Moon has no bright outline or false point marker');
 for(const [name,light] of [['right',[127,0,0]],['left',[-127,0,0]],['top',[0,-127,0]],['bottom',[0,127,0]]]){
  const s=disc(e,light);assert.equal(count(s)*2,area);
  for(let y=81;y<113;y++)for(let x=113;x<145;x++){
   const expected=pixel(full,x,y)&&({right:x>=129,left:x<=128,top:y<=96,bottom:y>=97}[name]);
   assert.equal(pixel(s,x,y),expected?1:0,`${name} at ${x},${y}`);
  }
 }
 const crescent=count(disc(e,[110,0,-64]))/area,gibbous=count(disc(e,[110,0,64]))/area;
 assert.ok(Math.abs(crescent-.25)<.035);assert.ok(Math.abs(gibbous-.75)<.035);
 fs.writeFileSync(path.join(root,'build/moon-full.scr'),Buffer.concat([full,Buffer.alloc(768,7)]));
});

test('the bright limb rotates with the map and mirrors towards the Sun',async()=>{
 const e=await start();
 for(const f of fixtures.filter(f=>[45,90,135,270].includes(f.phase))){
  setDate(e,f.utc);
  const north=norm([0,0,1].map((v,i)=>v-dot([0,0,1],f.moon)*f.moon[i]));
  const east=norm(cross(north,f.moon));
  for(const turn of [0,Math.PI/2,Math.PI])for(const off of [0,Math.PI/6]){
   const r=east.map((v,i)=>v*Math.cos(turn)+north[i]*Math.sin(turn));
   const u=north.map((v,i)=>v*Math.cos(turn)-east[i]*Math.sin(turn));
   const F=f.moon.map((v,i)=>v*Math.cos(off)-r[i]*Math.sin(off));
   const R=r.map((v,i)=>v*Math.cos(off)+f.moon[i]*Math.sin(off));
   const coeff=[...R,...u,...F].map(x=>Math.round(x*127));
   for(let i=0;i<9;i++)e.evaluate(`writeMemory(${symbols.coefficients+i},${coeff[i]&255})`);
   call(e,'make_tables');
   const z=dot(f.moon,F);
   const tangent=row=>row.map((v,i)=>v-dot(f.moon,row)/(1+z)*(f.moon[i]+F[i]));
   for(const mirror of [0,1]){
    put(e,'mirror_on',mirror);call(e,'moon_lighting');
    const expected=[dot(f.light,tangent(R))*(mirror?-1:1),-dot(f.light,tangent(u)),2*f.fraction-1];
    const actual=['moon_light_r','moon_light_d','moon_light_z'].map(k=>signed(byte(e,k))/127);
    actual.forEach((v,i)=>assert.ok(Math.abs(v-expected[i])<.05,`${f.phase}/${turn}/${off}/${mirror}: ${actual} vs ${expected}`));
   }
  }
 }
});

test('dark lunar surface occludes stars and clipping stays inside native video memory',async()=>{
 const e=await start();
 call(e,'clear_screen');e.evaluate('ramBanks[5].fill(255,0,6144)');
 put(e,'px',2);put(e,'py',2);put(e,'moon_diameter',32);
 put(e,'moon_light_r',0);put(e,'moon_light_d',0);put(e,'moon_light_z',-127);
 // Exclude the harness CALL trampoline/stack and the program's mutable state.
 const guard=()=>Buffer.from(e.evaluate('Array.from({length:48},(_,i)=>readMemory(0x5b10+i)).concat(Array.from({length:112},(_,i)=>readMemory(0x5b90+i)))'));
 const untouched=guard();
 call(e,'moon_raster');const s=bitmap(e);
 assert.equal(pixel(s,2,2),0);assert.equal(pixel(s,200,100),1);
 assert.deepEqual(guard(),untouched);
 put(e,'px',254);put(e,'py',190);call(e,'moon_raster');
 assert.equal(pixel(bitmap(e),254,190),0);assert.deepEqual(guard(),untouched);
});

test('finding the Moon and zooming to a proportional disc works through the real keyboard',async()=>{
 const e=await start();e.key('KeyF');wait(e,'finder_wait');
 for(const code of ['KeyM','KeyO','KeyO','KeyN']){e.key(code);wait(e,'finder_wait');}
 assert.equal(byte(e,'result_count'),1);e.key('Enter');wait(e);
 for(let i=0;i<6;i++)key(e,'KeyZ');
 assert.equal(byte(e,'zoom_index'),8);assert.ok(byte(e,'moon_diameter')>=28);
 assert.ok(byte(e,'px')<256&&byte(e,'py')<192);
 const az=word(e,'azimuth');key(e,'ArrowRight');assert.equal(word(e,'azimuth'),(az+28)&65535);
 fs.writeFileSync(path.join(root,'build/moon-zoom.scr'),Buffer.from(e.evaluate('Array.from(ramBanks[7].slice(0,6912))')));
});
