const assert = require('node:assert/strict');
const { test } = require('node:test');
const { createEmulator } = require('./emulator-harness.cjs');

async function start(model = '128K') {
    const e = createEmulator(undefined, { audio: true });
    await e.evaluate(`loadBuiltInModel('${model}')`);
    return e;
}

test('idle ROM menus remain silent even when audio frames arrive late', async () => {
    for (const model of ['48K', '128K']) {
        const e = await start(model);
        e.frames(200);
        for (const delay of [0, 0.012, 0.035, 0.1]) {
            const result = e.evaluate(`(() => {
                audioCtx.currentTime = nextAudioTime + ${delay};
                loop();
                return {
                    volumes: Array.from(ayRegisters.slice(8, 11)),
                    peak: Math.max(...audioCtx.lastBuffer.getChannelData(0).map(Math.abs))
                };
            })()`);
            assert.deepEqual(Array.from(result.volumes), [0, 0, 0]);
            assert.equal(result.peak, 0, `${model} idle output with ${delay}s delay`);
        }
    }
});

test('audio scheduling leaves a cushion at startup and after an underrun', async () => {
    const e = await start();
    assert.ok(e.evaluate('audioCtx.starts[0] - audioCtx.currentTime') >= 0.02);
    const result = e.evaluate(`(() => {
        audioCtx.currentTime = nextAudioTime + 0.035;
        loop();
        const recoveredStart = audioCtx.starts.at(-1);
        const recoveredEnd = nextAudioTime;
        audioCtx.currentTime += 0.02;
        loop();
        return { lead: recoveredStart - (audioCtx.currentTime - 0.02),
            contiguous: Math.abs(audioCtx.starts.at(-1) - recoveredEnd) < 1e-9 };
    })()`);
    assert.ok(result.lead >= 0.02);
    assert.equal(result.contiguous, true, 'On-time buffers must join without gaps');
});

test('held beeper and AY levels decay to silence without suppressing beeps', async () => {
    const e = await start();
    const result = e.evaluate(`(() => {
        const frame = getFrameTStates();
        const pulse = synthesizeAudioFrame([
            { t: frame / 4, val: 1 }, { t: frame * 3 / 4, val: 0 }
        ], []);
        let held = synthesizeAudioFrame([{ t: 0, val: 1 }], [
            { t: 0, register: 7, value: 63 }, { t: 0, register: 8, value: 15 }
        ]);
        for (let i = 0; i < 20; i++) held = synthesizeAudioFrame([], []);
        return { min: Math.min(...pulse), max: Math.max(...pulse),
            heldPeak: Math.max(...held.map(Math.abs)) };
    })()`);
    assert.ok(result.max > 0.4, 'Beeper rising edge must remain audible');
    assert.ok(result.min < -0.4, 'Beeper falling edge must remain audible');
    assert.equal(result.heldPeak, 0, 'A constant chip level must not become a buzz');
});

test('128K AY ports read back masked registers and leave the keyboard accessible', async () => {
    const e = await start();
    e.evaluate('writePort(0xFFFD, 1); writePort(0xBFFD, 255);');
    assert.equal(e.evaluate('readPort(0xFFFD)'), 15);
    e.evaluate('writePort(0xFFFD, 14); writePort(0xBFFD, 0);');
    assert.equal(e.evaluate('readPort(0xFFFD)'), 255); // Disconnected socket, input mode.
    e.dispatchKey('Digit1', 'keydown');
    assert.equal(e.evaluate('readPort(0xF7FE) & 1'), 0);
    e.dispatchKey('Digit1', 'keyup');
    assert.equal(e.evaluate('readPort(0xF7FE) & 1'), 1);
    assert.equal(e.evaluate('readPort(0x001F)'), 0); // No phantom joystick input.
});

test('48K has no AY device or AY audio', async () => {
    const e = await start('48K');
    e.evaluate('writePort(0xFFFD, 8); writePort(0xBFFD, 15);');
    assert.equal(e.evaluate('readPort(0xFFFD)'), 255);
    assert.equal(e.evaluate('ayRegisters[8]'), 0);
    assert.equal(e.evaluate('ayLog.length'), 0);
});

test('AY tone frequency follows the chip clock and all three mixer channels work', async () => {
    const e = await start();
    for (let channel = 0; channel < 3; channel++) {
        const result = e.evaluate(`(() => {
            const chip = new AY38912();
            chip.write(${channel * 2}, 100);
            chip.write(7, ${63 ^ (1 << channel)});
            chip.write(${8 + channel}, 15);
            const samples = Array.from({ length: 1001 }, () => chip.sample(16));
            return { edges: samples.filter((v, i) => i && v !== samples[i-1]).length,
                min: Math.min(...samples), max: Math.max(...samples) };
        })()`);
        assert.equal(result.edges, 10); // Toggle every 100 * 16 CPU T-states.
        assert.equal(result.min, 0);
        assert.equal(result.max, 1 / 3);
    }
});

test('AY noise produces a deterministic varying signal and mixer disable silences it', async () => {
    const e = await start();
    const result = e.evaluate(`(() => {
        const chip = new AY38912();
        chip.write(6, 3); chip.write(7, 0x37); chip.write(8, 15);
        const samples = Array.from({ length: 1000 }, () => chip.sample(96));
        chip.write(8, 0);
        return { min: Math.min(...samples), max: Math.max(...samples), silence: chip.sample(96) };
    })()`);
    assert.equal(result.min, 0);
    assert.equal(result.max, 1 / 3);
    assert.equal(result.silence, 0);
});

test('AY envelope shapes repeat, alternate or hold, and writing shape restarts them', async () => {
    const e = await start();
    const rising = Array.from({ length: 16 }, (_, i) => i);
    const falling = [...rising].reverse();
    const shapes = new Map([
        [0, [...falling, 0, 0]], [4, [...rising, 0, 0]],
        [8, [...falling, 15, 14]], [9, [...falling, 0, 0]],
        [10, [...falling, 0, 1]], [11, [...falling, 15, 15]],
        [12, [...rising, 0, 1]], [13, [...rising, 15, 15]],
        [14, [...rising, 15, 14]], [15, [...rising, 0, 0]]
    ]);
    for (const [shape, expected] of shapes) {
        const actual = e.evaluate(`(() => {
            const chip = new AY38912();
            chip.write(11, 2); chip.write(13, ${shape});
            const levels = [chip.envelopeStep ^ chip.attack];
            for (let i = 1; i < 18; i++) {
                chip.sample(64);
                levels.push(chip.envelopeStep ^ chip.attack);
            }
            chip.write(13, ${shape});
            return { levels, restarted: chip.envelopeStep ^ chip.attack };
        })()`);
        assert.deepEqual(Array.from(actual.levels), expected, `shape ${shape}`);
        assert.equal(actual.restarted, expected[0]);
    }
});

test('AY writes retain their timing within the Web Audio output buffer', async () => {
    const e = await start();
    const result = e.evaluate(`(() => {
        ayChip.reset(); ayLog = []; speakerLog = []; lastSpeakerState = 0; frameTStates = 0;
        for (const [register, value] of [[0,120], [7,62], [8,0]]) {
            writePort(0xFFFD, register); writePort(0xBFFD, value);
        }
        frameTStates = getFrameTStates() / 2;
        writePort(0xFFFD, 8); writePort(0xBFFD, 15);
        processAudioFrame([]);
        const data = audioCtx.lastBuffer.getChannelData(0);
        return { length: data.length, firstRange: Math.max(...data.slice(0,440)) - Math.min(...data.slice(0,440)),
            secondRange: Math.max(...data.slice(442)) - Math.min(...data.slice(442)),
            starts: audioCtx.starts.length };
    })()`);
    assert.equal(result.length, 882);
    assert.equal(result.firstRange, 0);
    assert.ok(result.secondRange > 0.1);
    assert.ok(result.starts >= 2);
});

test('audio toggle restores display focus; real keyboard events work after it', async () => {
    const e = await start();
    e.dispatchKey('KeyP', 'keydown');
    assert.equal(e.evaluate('keyboard[0xDFFE] & 1'), 0);
    e.click('btnAudio');
    assert.equal(e.evaluate('document.activeElement === container'), true);
    assert.equal(e.evaluate('audioGain.gain.value'), 0);
    assert.equal(e.evaluate('keyboard[0xDFFE] & 1'), 1); // Focus change releases held keys.
    e.click('btnAudio');
    assert.equal(e.evaluate('audioGain.gain.value'), 0.1);
    e.dispatchKey('Digit1', 'keydown');
    assert.equal(e.evaluate('readPort(0xF7FE) & 1'), 0);
    e.dispatchKey('Digit1', 'keyup');
    assert.equal(e.evaluate('readPort(0xF7FE) & 1'), 1);
});

test('Tab-focused controls keep their keyboard input until the display is focused', async () => {
    const e = await start();
    e.elements.get('btnSamples').focus();
    e.dispatchKey('Digit1', 'keydown');
    assert.equal(e.evaluate('readPort(0xF7FE) & 1'), 1);
});

test('suspended audio cannot stop CPU frames; reset clears the chip and held keys', async () => {
    const e = await start();
    e.evaluate(`audioCtx.state = 'suspended'; nextAudioTime = 100;
        writePort(0xFFFD, 8); writePort(0xBFFD, 15);`);
    const before = e.evaluate('z80.getState().r');
    e.frames(1);
    assert.notEqual(e.evaluate('z80.getState().r'), before);
    e.dispatchKey('KeyP', 'keydown');
    e.evaluate('resetSystem()');
    assert.equal(e.evaluate('ayRegisters[8]'), 0);
    assert.equal(e.evaluate('ayChip.registers[8]'), 0);
    assert.equal(e.evaluate('keyboard[0xDFFE] & 1'), 1);
});
