const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { createEmulator } = require('./emulator-harness.cjs');
const root=path.join(__dirname,'../..');
const symbols=Object.fromEntries(fs.readFileSync(path.join(root,'build/skyglobe.map'),'utf8').trim().split('\n').map(l=>{const [a,n]=l.split('=');return [n,parseInt(a,16)];}));
const byte=(e,n)=>e.evaluate(`readMemory(${symbols[n]})`);
const word=(e,n)=>e.evaluate(`readMemory(${symbols[n]}) | (readMemory(${symbols[n]+1}) << 8)`);
function put(e,n,v){e.evaluate(`writeMemory(${symbols[n]},${v&255})`);}
function putw(e,n,v){put(e,n,v);e.evaluate(`writeMemory(${symbols[n]+1},${(v>>8)&255})`);}
function wait(e,label='main_loop',limit=2400){
  let n=0;
  while(n<limit){
    if(e.evaluate(`(() => { const s=z80.getState();return s.pc===${symbols.irq} && ((readMemory(s.sp)|(readMemory(s.sp+1)<<8))===${symbols[label]+1});})()`)) return n;
    e.frames(10);n+=10;
  }
  throw Error(`No return to ${label}: `+JSON.stringify(e.evaluate('z80.getState()')));
}
function key(e,code,modifier){modifier?e.chord([modifier,code]):e.key(code);return wait(e);}
function screen(e){return Buffer.from(e.evaluate('Array.from(ramBanks[7].slice(0,6912))'));}
async function start(){const e=createEmulator();await e.evaluate('startSkyGlobe()');e.frames(200);wait(e);return e;}
function call(e,label,registers={}){
  return e.evaluate(`(() => {
    const saved=z80.getState();
    writeMemory(0x5b00,0xcd);writeMemory(0x5b01,${symbols[label]&255});writeMemory(0x5b02,${symbols[label]>>8});writeMemory(0x5b03,0x76);
    const s=z80.getState();Object.assign(s,{pc:0x5b00,sp:0x5b80,iff1:0,iff2:0,halted:false,do_delayed_ei:false,...${JSON.stringify(registers)}});z80.setState(s);
    let cycles=0;while(z80.getState().pc!==0x5b04 && cycles<40000000) cycles+=z80.run_instruction();
    const out=z80.getState();z80.setState(saved);if(out.pc!==0x5b04)throw Error("Native routine did not finish");return out;
  })()`);
}

module.exports={root,symbols,byte,word,put,putw,wait,key,screen,start,call};
