// The films' music and sound effects, synthesized here from nothing, so there is no license to clear. A film exposes
// window.CUES and its score picks the arrangement: "punchy" (demo.html) is a 140 BPM track in A minor with hits on
// the cuts; "editorial" (editorial.html) is a calm 100 BPM piece with soft sounds on the cues the page places and
// its lift on the logo; "keycaps" (keycaps.html) is 120 BPM in D minor, a click for every key that appears, an
// impact on the full keyboard, mouse clicks and wheel notches over a lighter groove, and a warm end card. render.cjs calls write() and muxes the result.
"use strict";
const fs = require("node:fs");

const SR = 48000;
const TAU = Math.PI * 2;
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);

// Seeded noise, so every render sounds the same.
function noise(seed) {
  let s = seed | 0;
  return () => {
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return (((t ^ (t >>> 14)) >>> 0) / 4294967296) * 2 - 1;
  };
}

// Zavalishin's state-variable filter. The cutoff may move every sample; bp and hp are left on the filter.
class SVF {
  constructor() { this.a = 0; this.b = 0; this.bp = 0; this.hp = 0; }
  lp(x, fc, q = 0.707) {
    const g = Math.tan((Math.PI * Math.min(fc, SR * 0.45)) / SR), k = 1 / q;
    const a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2;
    const v3 = x - this.b, v1 = a1 * this.a + a2 * v3, v2 = this.b + a2 * this.a + a3 * v3;
    this.a = 2 * v1 - this.a;
    this.b = 2 * v2 - this.b;
    this.bp = v1;
    this.hp = x - k * v1 - v2;
    return v2;
  }
  band(x, fc, q) { this.lp(x, fc, q); return this.bp; }
  high(x, fc, q) { this.lp(x, fc, q); return this.hp; }
}

// Band-limited saw (PolyBLEP), phase in [0, 1).
function saw(p, dt) {
  let v = 2 * p - 1;
  if (p < dt) { const t = p / dt; v -= t + t - t * t - 1; }
  else if (p > 1 - dt) { const t = (p - 1) / dt; v -= t * t + t + t + 1; }
  return v;
}

class Mix {
  constructor(seconds) {
    this.n = Math.ceil(seconds * SR);
    for (const k of ["L", "R", "rv", "dl"]) this[k] = new Float32Array(this.n);
    this.pump = new Float32Array(this.n).fill(1);
  }
  // Renders fn(t) for len seconds from t0 into the mix. duck is how much the kick's sidechain pumps it; rv and dl are
  // reverb and delay sends.
  voice(t0, len, fn, { gain = 1, pan = 0, rv = 0, dl = 0, duck = 0 } = {}) {
    const i0 = Math.round(t0 * SR), n = Math.round(len * SR);
    const gl = gain * Math.cos(((pan + 1) * Math.PI) / 4), gr = gain * Math.sin(((pan + 1) * Math.PI) / 4);
    for (let i = 0; i < n; i++) {
      const j = i0 + i;
      if (j >= this.n) break;
      let s = fn(i / SR);
      if (j < 0) continue;
      if (duck) s *= 1 - duck * (1 - this.pump[j]);
      this.L[j] += s * gl;
      this.R[j] += s * gr;
      this.rv[j] += s * gain * rv;
      this.dl[j] += s * gain * dl;
    }
  }
}

// Drums

function kick(m, t0, gain = 1) {
  const n = noise(1);
  let ph = 0;
  m.voice(t0, 0.42, (t) => {
    ph += (50 + 160 * Math.exp(-t / 0.026)) / SR;
    const body = Math.sin(TAU * ph) * Math.exp(-t / 0.17) * Math.min(1, t / 0.0008);
    return Math.tanh(1.9 * (body + n() * Math.exp(-t / 0.0022) * 0.4));
  }, { gain: 0.95 * gain });
}

function clap(m, t0, gain = 1) {
  const n = noise(2), f = new SVF();
  m.voice(t0, 0.4, (t) => {
    let env = 0;
    for (const o of [0, 0.011, 0.023]) if (t >= o) env = Math.max(env, Math.exp(-(t - o) / 0.006));
    if (t > 0.023) env = Math.max(env, 0.6 * Math.exp(-(t - 0.023) / 0.1));
    return f.band(n() * env, 1250, 1.3) * 2.6;
  }, { gain: 0.42 * gain, rv: 0.35 });
}

function snare(m, t0, gain = 1) {
  const n = noise(3), f = new SVF();
  let ph = 0;
  m.voice(t0, 0.22, (t) => {
    ph += 195 / SR;
    const tone = Math.sin(TAU * ph) * Math.exp(-t / 0.04);
    return f.high(n(), 1800, 0.8) * Math.exp(-t / 0.065) * 0.9 + tone * 0.5;
  }, { gain: 0.3 * gain, rv: 0.2 });
}

function hat(m, t0, gain = 1, open = false, pan = 0.25) {
  const n = noise(4), f = new SVF();
  m.voice(t0, open ? 0.3 : 0.07, (t) => f.high(n(), 8200, 0.9) * Math.exp(-t / (open ? 0.11 : 0.022)), { gain: 0.2 * gain, pan, rv: open ? 0.1 : 0 });
}

function crash(m, t0, gain = 1) {
  for (const [seed, pan] of [[5, -0.5], [6, 0.5]]) {
    const n = noise(seed), f = new SVF(), g = new SVF();
    m.voice(t0, 2.4, (t) => {
      const x = f.high(n(), 4200, 0.7);
      return (x + g.band(x, 7000, 3) * 0.6) * (Math.exp(-t / 0.9) * 0.8 + Math.exp(-t / 0.05) * 0.6);
    }, { gain: 0.16 * gain, pan, rv: 0.25 });
  }
}

// Sound effects

// A sub drop with a burst of low noise: the hit when the four modifiers become one key, and on the big cuts.
function boom(m, t0, gain = 1) {
  const n = noise(7), f = new SVF();
  let ph = 0;
  m.voice(t0, 1.2, (t) => {
    ph += (38 + 60 * Math.exp(-t / 0.18)) / SR;
    const sub = Math.sin(TAU * ph) * Math.exp(-t / 0.45);
    const thud = f.lp(n(), 260, 0.8) * Math.exp(-t / 0.12) * 1.6;
    return Math.tanh(1.6 * (sub + thud));
  }, { gain: 0.75 * gain, rv: 0.15 });
}

// Noise swept up into a cue; ends exactly at t0 + d.
function riser(m, t0, d, gain = 1, seed = 8) {
  const n = noise(seed), f = new SVF();
  let ph = 0;
  m.voice(t0, d, (t) => {
    const u = t / d;
    ph += (180 * Math.pow(8, u)) / SR;
    const x = f.band(n(), 350 * Math.pow(30, u), 1.4) * 1.8 + Math.sin(TAU * ph) * 0.25;
    return x * u * u;
  }, { gain: 0.5 * gain, rv: 0.3 });
}

// A short air swish, swept down; one per side so it spreads out.
function swish(m, t0, d = 0.32, gain = 1) {
  for (const [seed, pan] of [[9, -0.7], [10, 0.7]]) {
    const n = noise(seed), f = new SVF();
    m.voice(t0, d, (t) => {
      const u = t / d;
      return f.band(n(), 7000 * Math.pow(0.08, u), 1.2) * 2 * Math.sin(Math.PI * Math.min(1, u * 1.6)) * (1 - u);
    }, { gain: 0.32 * gain, pan, rv: 0.2 });
  }
}

// A keycap going down: a hard click with a woody body.
function clack(m, t0, gain = 1) {
  const n = noise(11), f = new SVF(), g = new SVF();
  m.voice(t0, 0.12, (t) => {
    const click = f.band(n(), 3800, 2) * Math.exp(-t / 0.004) * 3;
    const body = g.band(n(), 520, 4) * Math.exp(-t / 0.03) * 3;
    return click + body;
  }, { gain: 0.5 * gain, rv: 0.08 });
}

// A mouse button: tighter and higher than a key.
function mouseClick(m, t0, gain = 1) {
  const n = noise(12), f = new SVF();
  let ph = 0;
  m.voice(t0, 0.06, (t) => {
    ph += 2400 / SR;
    return f.band(n(), 5200, 2.5) * Math.exp(-t / 0.003) * 3 + Math.sin(TAU * ph) * Math.exp(-t / 0.008) * 0.6;
  }, { gain: 0.45 * gain, pan: 0.15 });
}

// A bright two-note blip for something appearing.
function pop(m, t0, from, to, gain = 1, pan = 0) {
  let ph = 0;
  m.voice(t0, 0.25, (t) => {
    const f = t < 0.045 ? mtof(from) : mtof(to);
    ph += f / SR;
    return (Math.sin(TAU * ph) + Math.sin(TAU * ph * 2) * 0.25) * Math.exp(-t / 0.07) * Math.min(1, t / 0.002);
  }, { gain: 0.22 * gain, pan, rv: 0.25, dl: 0.15 });
}

// A sine glide that follows the scroll knob up the curve.
function glide(m, t0, d, gain = 1) {
  let ph = 0;
  m.voice(t0, d + 0.15, (t) => {
    const u = Math.min(1, t / d);
    const e = u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
    ph += mtof(64 + 24 * e) / SR;
    const amp = Math.min(1, t / 0.1) * (t > d ? Math.max(0, 1 - (t - d) / 0.15) : 1);
    return (Math.sin(TAU * ph) + 0.3 * Math.sin(TAU * ph * 3)) * amp * (0.5 + 0.5 * Math.sin(TAU * 7 * t) ** 2);
  }, { gain: 0.09 * gain, rv: 0.3, dl: 0.2 });
}

// Instruments

function bass(m, t0, d, note, gain = 1) {
  const f = new SVF(), fr = mtof(note);
  let ph = 0;
  m.voice(t0, d + 0.03, (t) => {
    ph = (ph + fr / SR) % 1;
    const env = Math.min(1, t / 0.003) * (t > d ? Math.max(0, 1 - (t - d) / 0.03) : 1);
    const x = f.lp(saw(ph, fr / SR), 240 + 1700 * Math.exp(-t / 0.06), 0.9);
    return Math.tanh(1.7 * (x * 0.8 + Math.sin(TAU * ph) * 0.65)) * env;
  }, { gain: 0.3 * gain, duck: 0.85 });
}

function pluck(m, t0, note, { cut = 3200, gain = 1, pan = 0, decay = 0.11, dl = 0.3 } = {}) {
  const f = new SVF(), fr = mtof(note);
  let p1 = 0, p2 = 0.37;
  m.voice(t0, decay * 5, (t) => {
    const a = fr * 1.0035 / SR, b = fr * 0.9965 / SR;
    p1 = (p1 + a) % 1;
    p2 = (p2 + b) % 1;
    const x = (saw(p1, a) + saw(p2, b)) * 0.5;
    return f.lp(x, cut * (0.22 + 0.78 * Math.exp(-t / 0.045)), 1.1) * Math.exp(-t / decay) * Math.min(1, t / 0.002);
  }, { gain: 0.2 * gain, pan, rv: 0.15, dl, duck: 0.5 });
}

function pad(m, t0, d, notes, gain = 1, { cut = 1500, attack = 0.12, release = 0.5, duck = 0.7 } = {}) {
  for (const note of notes) {
    for (const [cents, pan] of [[-9, -0.6], [9, 0.6]]) {
      const f = new SVF(), dt = (mtof(note) * Math.pow(2, cents / 1200)) / SR;
      let p = (note * 0.618 + (cents > 0 ? 0.5 : 0)) % 1;
      m.voice(t0, d + release, (t) => {
        p = (p + dt) % 1;
        const env = Math.min(1, t / attack) * (t > d ? Math.max(0, 1 - (t - d) / release) : 1);
        return f.lp(saw(p, dt), typeof cut === "function" ? cut(t) : cut, 0.7) * env;
      }, { gain: 0.035 * gain, pan, rv: 0.4, duck });
    }
  }
}

// A felt piano: soft hammer, few partials, low notes ring longer.
function keys(m, t0, note, vel = 1, pan = 0) {
  const f = mtof(note), lp = new SVF(), n = noise(note * 7 + 1);
  let p1 = 0, p2 = 0, p3 = 0;
  m.voice(t0, 2.8, (t) => {
    p1 = (p1 + f / SR) % 1;
    p2 = (p2 + (f * 2.002) / SR) % 1;
    p3 = (p3 + (f * 3.003) / SR) % 1;
    const env = Math.min(1, t / 0.006) * Math.exp(-t / (0.9 + 60 / f));
    const x = Math.sin(TAU * p1) + 0.45 * Math.sin(TAU * p2) * Math.exp(-t / 0.5) + 0.2 * Math.sin(TAU * p3) * Math.exp(-t / 0.25);
    return lp.lp(x * env + n() * Math.exp(-t / 0.008) * 0.15, 900 + 2600 * vel * Math.exp(-t / 0.3), 0.7) * vel;
  }, { gain: 0.16, pan, rv: 0.45, dl: 0.16, duck: 0.15 });
}

// The soft low pulse under the calm score.
function thump(m, t0, gain = 1) {
  let ph = 0;
  m.voice(t0, 0.5, (t) => {
    ph += (52 + 30 * Math.exp(-t / 0.04)) / SR;
    return Math.sin(TAU * ph) * Math.exp(-t / 0.18) * Math.min(1, t / 0.004);
  }, { gain: 0.42 * gain });
}

function softBass(m, t0, d, note, gain = 1) {
  const f = new SVF(), fr = mtof(note);
  let ph = 0;
  m.voice(t0, d + 0.15, (t) => {
    ph = (ph + fr / SR) % 1;
    const env = Math.min(1, t / 0.02) * (t > d ? Math.max(0, 1 - (t - d) / 0.15) : 1);
    return f.lp(Math.sin(TAU * ph) + 0.35 * saw(ph, fr / SR), 420, 0.7) * env;
  }, { gain: 0.2 * gain, duck: 0.4 });
}

function shaker(m, t0, gain = 1) {
  const n = noise(14), f = new SVF();
  m.voice(t0, 0.12, (t) => f.band(n(), 6500, 1.2) * Math.min(1, t / 0.006) * Math.exp(-t / 0.035) * 2, { gain: 0.12 * gain, pan: 0.3 });
}

// Interface sounds for the calm cut: small, dry and close, never whooshes.

function typeTick(m, t0, gain = 1) {
  const n = noise(Math.round(t0 * 1000)), f = new SVF(), g = new SVF();
  m.voice(t0, 0.04, (t) => f.band(n(), 3600, 2) * Math.exp(-t / 0.0025) * 2.4 + g.band(n(), 1100, 3) * Math.exp(-t / 0.008) * 1.2,
    { gain: 0.22 * gain, pan: Math.sin(t0 * 91) * 0.25 });
}

function thock(m, t0, gain = 1) {
  const n = noise(15), f = new SVF(), g = new SVF();
  m.voice(t0, 0.14, (t) => g.band(n(), 330, 3) * Math.exp(-t / 0.035) * 4 + f.band(n(), 2600, 2) * Math.exp(-t / 0.003) * 2,
    { gain: 0.5 * gain, rv: 0.1 });
}

function tick(m, t0, gain = 1) {
  let ph = 0;
  m.voice(t0, 0.05, (t) => {
    ph += 2400 / SR;
    return Math.sin(TAU * ph) * Math.exp(-t / 0.012) * Math.min(1, t / 0.0008);
  }, { gain: 0.11 * gain, rv: 0.15, pan: Math.sin(t0 * 37) * 0.3 });
}

function tap(m, t0, gain = 1) {
  const n = noise(16), f = new SVF();
  let ph = 0;
  m.voice(t0, 0.08, (t) => {
    ph += 900 / SR;
    return f.band(n(), 3000, 2) * Math.exp(-t / 0.003) * 1.8 + Math.sin(TAU * ph) * Math.exp(-t / 0.025) * 0.8;
  }, { gain: 0.32 * gain, rv: 0.1 });
}

function detent(m, t0, gain = 1) {
  const n = noise(Math.round(t0 * 977)), f = new SVF(), g = new SVF();
  m.voice(t0, 0.03, (t) => f.band(n(), 1800, 4) * Math.exp(-t / 0.004) * 3 + g.high(n(), 5000, 0.7) * Math.exp(-t / 0.001),
    { gain: 0.3 * gain, pan: -0.1 });
}

// A small bell for the hyper key: inharmonic partials over a soft thump.
function chime(m, t0, gain = 1) {
  const f = mtof(84);
  const parts = [[1, 1.6, 1], [2.0, 0.9, 0.4], [3.01, 0.5, 0.25], [4.2, 0.3, 0.15]];
  const ph = parts.map(() => 0);
  m.voice(t0, 2.2, (t) => {
    let x = 0;
    parts.forEach(([r, d, a], i) => {
      ph[i] += (f * r) / SR;
      x += Math.sin(TAU * ph[i]) * a * Math.exp(-t / d);
    });
    return x * Math.min(1, t / 0.002);
  }, { gain: 0.1 * gain, rv: 0.55, dl: 0.2 });
  thump(m, t0, 0.6);
}

// A chord hit for the big moments.
function stab(m, t0, notes, gain = 1) {
  notes.forEach((note, i) => {
    const f = new SVF(), dt = mtof(note) / SR;
    let p = i * 0.21;
    m.voice(t0, 1.3, (t) => {
      p = (p + dt) % 1;
      return f.lp(saw(p, dt), 500 + 7000 * Math.exp(-t / 0.12), 0.9) * Math.exp(-t / 0.38) * Math.min(1, t / 0.002);
    }, { gain: 0.11 * gain, pan: (i / (notes.length - 1)) * 1.2 - 0.6, rv: 0.45, dl: 0.2 });
  });
}

// Effects buses

function freeverb(input, { room = 0.8, damp = 0.35, offset = 0 } = {}) {
  const scale = SR / 44100;
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map((d) => ({ buf: new Float32Array(Math.round((d + offset) * scale)), i: 0, z: 0 }));
  const aps = [556, 441, 341, 225].map((d) => ({ buf: new Float32Array(Math.round((d + offset) * scale)), i: 0 }));
  const out = new Float32Array(input.length);
  for (let n = 0; n < input.length; n++) {
    const x = input[n] * 0.015;
    let s = 0;
    for (const c of combs) {
      const y = c.buf[c.i];
      c.z = y * (1 - damp) + c.z * damp;
      c.buf[c.i] = x + c.z * room;
      c.i = (c.i + 1) % c.buf.length;
      s += y;
    }
    for (const a of aps) {
      const b = a.buf[a.i];
      a.buf[a.i] = s + b * 0.5;
      a.i = (a.i + 1) % a.buf.length;
      s = b - s;
    }
    out[n] = s;
  }
  return out;
}

function pingpong(input, time, fb) {
  const D = Math.round(time * SR), n = input.length;
  const L = new Float32Array(n), R = new Float32Array(n), f = new SVF();
  for (let i = 0; i < n; i++) {
    const r = i >= D ? R[i - D] : 0, l = i >= D ? L[i - D] : 0;
    L[i] = input[i] + f.lp(r, 3500) * fb;
    R[i] = l;
  }
  // The wet signal is the line delayed once more: left, then right, then left...
  const wl = new Float32Array(n), wr = new Float32Array(n);
  for (let i = D; i < n; i++) { wl[i] = L[i - D]; wr[i] = R[i - D]; }
  return [wl, wr];
}

const CHORDS = {
  Am: { bass: 45, pad: [57, 60, 64], arp: [69, 72, 76, 81] },
  F: { bass: 41, pad: [57, 60, 65], arp: [69, 72, 77, 81] },
  C: { bass: 48, pad: [55, 60, 64], arp: [67, 72, 76, 79] },
  G: { bass: 43, pad: [55, 59, 62], arp: [67, 71, 74, 79] },
};
// One chord per bar: the intro, the three feature scenes (two bars each) and the outro.
const PROGRESSION = ["Am", "F", "C", "G", "Am", "F", "G", "C", "C"];

function punchy(c) {
  const B = 60 / c.BPM, at = (beat) => beat * B;
  const drop = Math.round(c.T2 / B), outro = Math.round(c.T5 / B), end = Math.round(c.TOTAL / B);
  const chord = (beat) => CHORDS[PROGRESSION[Math.min(PROGRESSION.length - 1, Math.floor(beat / 4))]];
  const m = new Mix(c.TOTAL);

  // The kick drives the sidechain, so lay it down first.
  const kicks = [0];
  for (let b = drop; b < outro; b++) kicks.push(b);
  kicks.push(outro);
  for (let i = 0, k = 0; i < m.n; i++) {
    while (k + 1 < kicks.length && i / SR >= at(kicks[k + 1])) k++;
    const since = i / SR - at(kicks[k]);
    m.pump[i] = since < 0 ? 1 : 1 - Math.exp(-since / 0.09);
  }
  for (const b of kicks) kick(m, at(b), b === 0 || b === outro ? 1.1 : 1);

  // Intro: a hit on frame 0, then a bar that builds into the drop on the first cut.
  stab(m, 0, [...CHORDS.Am.pad, 69], 1.1);
  crash(m, 0, 0.9);
  boom(m, 0, 0.6);
  pad(m, 0, at(drop), CHORDS.Am.pad, 0.8);
  for (let s = 0; s < drop * 4; s++) {
    const u = s / (drop * 4);
    pluck(m, at(s / 4), CHORDS.Am.arp[[0, 1, 2, 3, 2, 1, 0, 2][s % 8]], { cut: 700 * Math.pow(5, u), gain: 0.6 + 0.4 * u, pan: s % 2 ? 0.3 : -0.3 });
    if (s >= 4) hat(m, at(s / 4), (s % 2 ? 0.35 : 0.6) * u);
  }
  for (let s = 8; s < 12; s += 2) snare(m, at(s / 4), 0.35 + 0.1 * (s - 8));
  for (let s = 12; s < 16; s++) snare(m, at(s / 4), 0.6 + 0.1 * (s - 12));
  riser(m, at(1), at(drop - 1), 0.8);

  // Feature scenes: the full groove.
  for (let b = drop; b < outro; b++) {
    const ch = chord(b), bar = b % 4;
    if (bar === 0) pad(m, at(b), at(4), ch.pad);
    if ((b - drop) % 2 === 1) clap(m, at(b));
    for (let s = 0; s < 4; s++) {
      const t = at(b + s / 4);
      hat(m, t, [0.45, 0.25, 0.75, 0.3][s], false, s % 2 ? 0.3 : 0.15);
      if (s) bass(m, t, at(0.2), ch.bass + (bar === 3 && s === 3 ? 12 : 0));
      const step = (b - drop) * 4 + s;
      // The arp opens up as the scroll knob climbs the curve.
      const u = Math.min(1, Math.max(0, (t - c.SWEEP) / c.SWEEP_D));
      const cut = t < c.SWEEP ? 3000 : 3000 * Math.pow(3, u);
      pluck(m, t, ch.arp[[0, 1, 2, 3, 2, 1, 3, 2][step % 8]] + (u > 0.6 ? 12 : 0), { cut, pan: s % 2 ? 0.35 : -0.35 });
    }
    hat(m, at(b + 0.5), 0.5, true, -0.2);
  }

  // Hyper key: the key goes down, splits into four, and the four slam back together.
  clack(m, c.DOWN, 1.6);
  swish(m, c.SPLIT, 0.3, 1);
  [69, 72, 77, 81].forEach((note, i) => pop(m, c.SPLIT + 0.05 + i * 0.04, note, note + 12, 1.1, -0.45 + i * 0.3));
  riser(m, c.MERGE - 0.25, c.HIT - (c.MERGE - 0.25), 1.2, 13);
  boom(m, c.HIT, 1.2);
  crash(m, c.HIT, 0.8);
  stab(m, c.HIT, [...CHORDS.C.pad, 72], 0.9);

  // Buttons: click Add Rule, press the mouse button, the rule pops in.
  mouseClick(m, c.CLICK, 1.5);
  mouseClick(m, c.PRESS, 1.8);
  boom(m, c.PRESS, 0.35);
  pop(m, c.ROW, 76, 83, 1.4, 0.2);

  // Scrolling: a tone glides up with the knob.
  glide(m, c.SWEEP, c.SWEEP_D);

  // Cuts: a swish out of each scene and a crash into the next.
  for (const t of [c.T3, c.T4]) {
    riser(m, t - 0.4, 0.4, 0.6, Math.round(t * 100));
    snare(m, t - at(0.5), 0.7);
    snare(m, t - at(0.25), 0.9);
    crash(m, t, 0.5);
  }
  for (let s = (outro - 2) * 4; s < outro * 4; s++) snare(m, at(s / 4), 0.4 + 0.6 * (s - (outro - 2) * 4) / 8);
  riser(m, at(outro - 2), at(2), 1);

  // Outro: one last hit, then the C chord rings out under the logo.
  boom(m, at(outro), 1);
  crash(m, at(outro), 1);
  stab(m, at(outro), [...CHORDS.C.pad, 72, 76], 1.2);
  pad(m, at(outro), at(end - outro) - 0.5, CHORDS.C.pad, 1.2);
  bass(m, at(outro), at(2), 36, 1);
  for (let s = 0; s < (end - outro) * 4; s++) {
    const u = s / ((end - outro) * 4);
    pluck(m, at(outro + s / 4), CHORDS.C.arp[[0, 1, 2, 3, 2, 1, 3, 2][s % 8]] + 12, { cut: 4000 * Math.pow(0.15, u), gain: 0.7 * (1 - u), pan: s % 2 ? 0.4 : -0.4, decay: 0.16 });
    if (s % 2 === 0 && u < 0.5) hat(m, at(outro + s / 4), 0.3 * (1 - 2 * u));
  }

  return master(m, at(0.75), { room: 0.8, wet: 2.4, drive: 1.2 });
}

// Delay and reverb buses, a high-pass under 30 Hz, soft clipping and a peak at -2 dBFS.
function master(m, delay, { room, wet, drive }) {
  const [dlL, dlR] = pingpong(m.dl, delay, 0.4);
  const rvL = freeverb(m.rv, { room }), rvR = freeverb(m.rv, { room, offset: 23 });
  // Rumble under 30 Hz only eats headroom; phones can't play it.
  const L = new Float32Array(m.n), R = new Float32Array(m.n), hl = new SVF(), hr = new SVF();
  const fadeOut = Math.round(0.3 * SR);
  for (let i = 0; i < m.n; i++) {
    const g = Math.min(1, i / 96) * Math.min(1, (m.n - i) / fadeOut);
    L[i] = Math.tanh(drive * hl.high(m.L[i] + dlL[i] * 0.5 + rvL[i] * wet, 30)) * g;
    R[i] = Math.tanh(drive * hr.high(m.R[i] + dlR[i] * 0.5 + rvR[i] * wet, 30)) * g;
  }
  // Peak at -2 dBFS, so the AAC encode has room for its overshoot.
  let peak = 0;
  for (let i = 0; i < m.n; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
  for (let i = 0; i < m.n; i++) { L[i] *= 0.79 / peak; R[i] *= 0.79 / peak; }
  return [L, R];
}

const ED = {
  Am9: { bass: 45, pad: [57, 60, 64, 67, 71] },
  Fmaj7: { bass: 41, pad: [53, 57, 60, 64] },
  G6: { bass: 43, pad: [55, 59, 62, 64] },
  Am7: { bass: 45, pad: [57, 60, 64, 67] },
  Em7: { bass: 40, pad: [52, 55, 59, 62] },
  Gsus4: { bass: 43, pad: [55, 60, 62, 67] },
  Cmaj9: { bass: 36, pad: [55, 60, 64, 71, 74] },
};

function editorial(c) {
  const B = 60 / c.BPM, BAR = 4 * B, bars = Math.round(c.TOTAL / BAR), lift = Math.round(c.LIFT / BAR);
  const m = new Mix(c.TOTAL);
  // Two bars of intro on Am9, then Fmaj7 G6 Am7 Em7 under the cards, a Gsus4 bar that leans in, and Cmaj9 on the logo.
  const chord = (bar) => ED[bar < 2 ? "Am9" : bar < lift - 1 ? ["Fmaj7", "G6", "Am7", "Em7"][(bar - 2) % 4] : bar === lift - 1 ? "Gsus4" : "Cmaj9"];

  const pulses = [];
  for (let bar = 2; bar < bars; bar++) for (let b = 0; b < 4; b++) if (bar < lift + 1 || b === 0) pulses.push(bar * BAR + b * B);
  for (let i = 0, k = -1; i < m.n; i++) {
    while (k + 1 < pulses.length && i / SR >= pulses[k + 1]) k++;
    m.pump[i] = k < 0 ? 1 : 1 - Math.exp(-(i / SR - pulses[k]) / 0.12);
  }

  for (let bar = 0; bar < bars; bar++) {
    const t = bar * BAR, ch = chord(bar), notes = ch.pad.map((n) => n + 12);
    const role = bar < 2 ? "intro" : bar < lift - 1 ? "mid" : bar === lift - 1 ? "build" : bar === lift ? "lift" : "tail";
    const padGain = { intro: 0.75, mid: 0.9, build: 1.1, lift: 1.5, tail: 1.3 }[role];
    const cut = role === "build" ? (u) => 1200 + 1800 * (u / BAR) : role === "lift" || role === "tail" ? 2200 : role === "intro" ? 1000 : 1300;
    pad(m, t, BAR, ch.pad, padGain, { cut, attack: role === "lift" ? 0.05 : 0.4, release: role === "tail" ? 1.6 : 0.9, duck: 0.3 });

    if (role === "intro") {
      [[0, 0, 0.6], [1.5, 2, 0.45], [2, 1, 0.5], [3, 4 % notes.length, 0.45]].forEach(([b, k, v]) => keys(m, t + b * B, notes[k % notes.length], v, 0.2));
    } else if (role === "mid") {
      [0, 2, 1, 3, 2, 4, 3, 1].forEach((k, s) => {
        if (bar % 2 === 1 && s >= 6) return;
        keys(m, t + (s * B) / 2, notes[k % notes.length], (s % 2 ? 0.45 : 0.7) * (0.9 + 0.1 * Math.sin(bar * 3 + s)), s % 2 ? 0.3 : -0.2);
      });
      softBass(m, t, 2 * B - 0.05, ch.bass, 1);
      softBass(m, t + 2 * B, 2 * B - 0.05, ch.bass + (bar % 2 ? 7 : 0), 0.9);
      if (bar >= 7) for (let s = 0; s < 8; s++) shaker(m, t + (s * B) / 2, s % 2 ? 0.5 : 1);
    } else if (role === "build") {
      for (let s = 0; s < 16; s++) keys(m, t + (s * B) / 4, notes[s % notes.length] + (s >= 8 ? 12 : 0), 0.35 + 0.4 * (s / 15), s % 2 ? 0.35 : -0.35);
      softBass(m, t, BAR - 0.05, ch.bass, 1);
    } else if (role === "lift") {
      notes.forEach((n, k) => keys(m, t + k * 0.012, n, 0.95, -0.4 + k * 0.2));
      keys(m, t, ch.bass + 12, 0.9);
      [1, 2, 3, 4, 3, 2, 1, 2].forEach((k, s) => s && keys(m, t + (s * B) / 2, notes[k % notes.length] + 12, 0.5, s % 2 ? 0.4 : -0.4));
      softBass(m, t, BAR + 0.4, ch.bass, 1.5);
      for (let b = 0; b < 4; b++) kick(m, t + b * B, 0.55);
      for (let s = 0; s < 8; s++) shaker(m, t + (s * B) / 2, s % 2 ? 0.6 : 1.1);
    } else {
      keys(m, t, notes[0], 0.6, -0.2);
      keys(m, t + 2 * B, notes[2], 0.45, 0.2);
    }
  }
  for (const p of pulses) thump(m, p, p >= c.LIFT ? 1 : 0.8);

  const play = { type: typeTick, keydown: thock, tick, tap, click: mouseClick, chime, detent };
  for (const { t, kind, gain } of c.sfx) play[kind](m, t, kind === "click" ? 0.55 * gain : gain);

  return master(m, 0.75 * B, { room: 0.86, wet: 3.2, drive: 1.0 });
}

const KC = {
  Dm9: { bass: 38, pad: [57, 60, 62, 64, 65] },
  Bbmaj7: { bass: 46, pad: [58, 62, 65, 69] },
  Gm9: { bass: 43, pad: [55, 58, 62, 65, 69] },
  Fmaj9: { bass: 41, pad: [57, 60, 64, 67] },
  C6: { bass: 48, pad: [55, 60, 64, 69] },
  Bbmaj9: { bass: 46, pad: [57, 60, 62, 65] },
  FA: { bass: 45, pad: [57, 60, 65, 69] },
};

function keycaps(c) {
  const B = 60 / c.BPM, BAR = 4 * B, bars = Math.round(c.TOTAL / BAR);
  const m = new Mix(c.TOTAL);
  // Two bars over the hero, a bar that builds as the keys multiply, the impact on the full keyboard and a bar of
  // groove under it, three lighter bars for the mouse, then the end card on Bbmaj9, moving to F as the word swaps.
  const PROG = ["Dm9", "Bbmaj7", "Gm9", "Fmaj9", "C6", "Dm9", "Bbmaj7", "C6", "Bbmaj9", "FA", "Fmaj9"];
  const roleAt = (t) => (t < c.IMPACT - 0.01 ? (t < 2 * BAR ? "intro" : "build") : t < c.MOUSE - 0.01 ? "drive" : t < c.END - 0.01 ? "mouse" : "end");

  const pulses = [];
  for (let b = 0; b * B < c.TOTAL - 0.01; b++) {
    const t = b * B, role = roleAt(t);
    if (role !== "end" || b % 4 === 0) pulses.push(t);
  }
  for (let i = 0, k = -1; i < m.n; i++) {
    while (k + 1 < pulses.length && i / SR >= pulses[k + 1]) k++;
    m.pump[i] = k < 0 ? 1 : 1 - Math.exp(-(i / SR - pulses[k]) / 0.12);
  }

  for (let bar = 0; bar < bars; bar++) {
    const t = bar * BAR, ch = KC[PROG[bar]], notes = ch.pad.map((n) => n + 12), role = roleAt(t);
    const gain = { intro: 0.6, build: 0.85, drive: 1.0, mouse: 0.85, end: 1.3 }[role];
    const cut = role === "build" ? (u) => 900 + 2200 * (u / BAR) : { intro: 900, drive: 1900, mouse: 1500, end: 1600 }[role];
    pad(m, t, BAR, ch.pad, gain, { cut, attack: role === "drive" ? 0.05 : 0.35, release: role === "end" && bar === bars - 1 ? 1.4 : 0.8, duck: 0.35 });
    if (role === "intro") {
      [[0, 0, 0.45], [2, 2, 0.4], [3, 3, 0.35]].forEach(([b, k, v]) => keys(m, t + b * B, notes[k % notes.length], v, 0.2));
    } else if (role === "build") {
      for (let s = 0; s < 8; s++) keys(m, t + (s * B) / 2, notes[s % notes.length] + (s >= 4 ? 12 : 0), 0.35 + 0.3 * (s / 7), s % 2 ? 0.3 : -0.3);
      softBass(m, t, 2 * B - 0.05, ch.bass, 0.9);
      softBass(m, t + 2 * B, 2 * B - 0.05, ch.bass, 1);
      for (let s = 8; s < 16; s++) shaker(m, t + (s * B) / 4, 0.4 + 0.6 * ((s - 8) / 7));
    } else if (role === "drive") {
      [0, 2, 1, 3, 2, 4, 3, 1].forEach((k, s) => keys(m, t + (s * B) / 2, notes[k % notes.length], s % 2 ? 0.4 : 0.55, s % 2 ? 0.3 : -0.25));
      for (let s = 0; s < 8; s++) {
        softBass(m, t + (s * B) / 2, B / 2 - 0.04, ch.bass + (s === 7 ? 12 : 0), 1.1);
        shaker(m, t + (s * B) / 2, s % 2 ? 0.6 : 1);
      }
    } else if (role === "mouse") {
      [0, 2, 1, 3, 2, 1, 3, 2].forEach((k, s) => s % 2 === 0 && keys(m, t + (s * B) / 2, notes[k % notes.length], 0.45, s % 4 ? 0.3 : -0.25));
      for (let b = 0; b < 4; b++) softBass(m, t + b * B, B - 0.05, ch.bass + (b === 3 ? 7 : 0), 0.9);
      for (let s = 0; s < 8; s++) shaker(m, t + (s * B) / 2, s % 2 ? 0.3 : 0.5);
    } else {
      [0, 1, 2, 3].forEach((k) => keys(m, t + k * B, notes[[0, 2, 1, 3][k] % notes.length], bar === bars - 1 ? 0.4 - 0.08 * k : 0.5, k % 2 ? 0.3 : -0.3));
      softBass(m, t, BAR - 0.05, ch.bass, 1.1);
    }
  }
  for (const p of pulses) {
    const role = roleAt(p), beat = Math.round(p / B);
    if (role === "drive" || (role === "mouse" && beat % 2 === 0)) kick(m, p, role === "drive" ? 0.6 : 0.45);
    else thump(m, p, role === "end" ? 0.7 : role === "mouse" ? 0.4 : 0.45 + 0.5 * (p / c.IMPACT));
  }

  // The full keyboard lands; then it scatters.
  riser(m, c.IMPACT - 1.2, 1.2, 0.7);
  boom(m, c.IMPACT, 0.9);
  crash(m, c.IMPACT, 0.55);
  stab(m, c.IMPACT, KC.Fmaj9.pad.map((n) => n + 12), 0.8);
  swish(m, c.SCATTER, 0.5, 1.0);
  stab(m, c.MOUSE, KC.Dm9.pad.map((n) => n + 12), 0.45);
  chime(m, c.SWAP, 0.45);

  const play = { clack, tick, click: mouseClick, detent };
  for (const { t, kind, gain } of c.sfx) play[kind](m, t, gain);
  return master(m, 0.75 * B, { room: 0.84, wet: 2.8, drive: 1.05 });
}

function write(file, cues) {
  const score = { editorial, keycaps }[cues.score] || punchy;
  const [L, R] = score(cues);
  const buf = Buffer.alloc(44 + L.length * 4);
  buf.write("RIFF", 0); buf.writeUInt32LE(36 + L.length * 4, 4); buf.write("WAVE", 8);
  buf.write("fmt ", 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34);
  buf.write("data", 36); buf.writeUInt32LE(L.length * 4, 40);
  for (let i = 0; i < L.length; i++) {
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i])) * 32767), 44 + i * 4);
    buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[i])) * 32767), 46 + i * 4);
  }
  fs.writeFileSync(file, buf);
}

module.exports = { write };
