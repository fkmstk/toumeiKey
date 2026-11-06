// タイプ音の合成（音源ファイルなし）。Swift 版 SoundEngine と同じレシピを WebAudio で再生する。
import * as store from "./store.js";

const SR = 44100;
const PRESET_GAIN = { thock: 0.55, clicky: 0.45, soft: 0.55, typewriter: 0.4, pop: 0.4 };

function biquad(type, f, q = 0.707) {
  const w = (2 * Math.PI * f) / SR, al = Math.sin(w) / (2 * q), c = Math.cos(w), a0 = 1 + al;
  let b0, b1, b2;
  if (type === "bp") { b0 = al / a0; b1 = 0; b2 = -al / a0; }
  else { b0 = (1 - c) / 2 / a0; b1 = (1 - c) / a0; b2 = (1 - c) / 2 / a0; }
  const a1 = (-2 * c) / a0, a2 = (1 - al) / a0;
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  return (x) => { const y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x; y2 = y1; y1 = y; return y; };
}
const noise = () => Math.random() * 2 - 1;
const env = (t, tau) => (t < 0 ? 0 : Math.exp(-t / tau));
const attack = (t) => Math.min(1, t / 0.0004);

function render(duration, peak, gen) {
  const n = Math.floor(duration * SR);
  const d = new Float32Array(n);
  for (let i = 0; i < n; i++) d[i] = gen(i / SR);
  const fade = Math.min(n, Math.floor(0.008 * SR));
  for (let i = 0; i < fade; i++) d[n - 1 - i] *= i / fade;
  let m = 0;
  for (const v of d) m = Math.max(m, Math.abs(v));
  const k = m > 0 ? peak / m : 0;
  for (let i = 0; i < n; i++) d[i] *= k;
  return d;
}

function synth(preset, p, s) {
  switch (preset) {
    case "thock": {
      // 小さな木を軽く叩いたような「コトッ」
      const tap = biquad("lp", 2200 * p), tone = biquad("lp", 2600);
      let phase = 0;
      return render(0.06 * s, 0.55, (t) => {
        const w1 = Math.sin(2 * Math.PI * 720 * p * t) * env(t, 0.0045 * s) * 0.55;
        const w2 = Math.sin(2 * Math.PI * 1180 * p * t) * env(t, 0.0028 * s) * 0.28;
        const f = 165 * p * (1 + 0.35 * Math.exp(-t / 0.003));
        phase += (2 * Math.PI * f) / SR;
        const thump = Math.sin(phase) * env(t, 0.008 * s) * 0.42;
        const touch = tap(noise()) * env(t, 0.001) * 0.22;
        return tone(w1 + w2 + thump + touch) * Math.min(1, t / 0.0008);
      });
    }
    case "clicky": {
      const bp1 = biquad("bp", 4600 * p, 2.2), bp2 = biquad("bp", 3700 * p, 2.0);
      return render(0.07 * s, 0.8, (t) => {
        const c1 = bp1(noise()) * env(t, 0.0014) * 1.2;
        const ring = Math.sin(2 * Math.PI * 3150 * p * t) * env(t, 0.004) * 0.25;
        const c2 = bp2(noise()) * env(t - 0.026 * s, 0.0018) * 0.7;
        const body = Math.sin(2 * Math.PI * 390 * p * t) * env(t, 0.007) * 0.3;
        return (c1 + ring + c2 + body) * attack(t);
      });
    }
    case "soft": {
      const lp = biquad("lp", 1300 * p);
      return render(0.07 * s, 0.7, (t) => (lp(noise()) * env(t, 0.0075 * s) * 0.8 + Math.sin(2 * Math.PI * 150 * p * t) * env(t, 0.012 * s) * 0.4) * attack(t));
    }
    case "typewriter": {
      const bp = biquad("bp", 2300 * p, 0.8);
      return render(0.16 * s, 0.85, (t) => {
        const strike = bp(noise()) * env(t, 0.003) * 1.2;
        const metal = (Math.sin(2 * Math.PI * 1760 * p * t) * 0.2 + Math.sin(2 * Math.PI * 2940 * p * t) * 0.13) * env(t, 0.028 * s);
        const thump = Math.sin(2 * Math.PI * 120 * p * t) * env(t, 0.02) * 0.45;
        return (strike + metal + thump) * attack(t);
      });
    }
    case "pop": {
      let phase = 0;
      return render(0.07 * s, 0.7, (t) => {
        const f = ((340 + 900 * (1 - Math.exp(-t / 0.009))) * p) / s;
        phase += (2 * Math.PI * f) / SR;
        return Math.sin(phase) * Math.min(1, t / 0.001) * env(t, 0.018 * s);
      });
    }
  }
  return new Float32Array(1);
}

const missWave = () => render(0.12, 0.6, (t) => {
  const x = Math.sin(2 * Math.PI * 155 * t) + 0.5 * Math.sin(2 * Math.PI * 310 * t);
  return Math.tanh(2.2 * x) * Math.min(1, t / 0.002) * env(t, 0.045);
});
const chimeWave = () => render(0.5, 0.6, (t) => {
  const note = (f, t0) => { const u = t - t0; return u < 0 ? 0 : (Math.sin(2 * Math.PI * f * u) + 0.18 * Math.sin(4 * Math.PI * f * u)) * Math.min(1, u / 0.003) * env(u, 0.16); };
  return note(1318.5, 0) + note(1760, 0.07);
});

export class SoundEngine {
  constructor() {
    this.ctx = null;
    this.bufs = null;
    this.last = -1;
  }

  /** 最初の打鍵で AudioContext を作る（ブラウザの自動再生制限のため） */
  ensure() {
    if (!this.ctx) {
      this.ctx = new AudioContext({ sampleRate: SR, latencyHint: "interactive" });
      const toBuf = (d) => { const b = this.ctx.createBuffer(1, d.length, SR); b.copyToChannel(d, 0); return b; };
      const pitches = [0.93, 0.96, 0.98, 1.0, 1.02, 1.04, 1.07];
      this.bufs = { key: {}, space: {} };
      for (const p of ["thock", "clicky", "soft", "typewriter", "pop"]) {
        this.bufs.key[p] = pitches.map((x) => toBuf(synth(p, x, 1)));
        this.bufs.space[p] = [0.76, 0.8].map((x) => toBuf(synth(p, x, 1.5)));
      }
      this.bufs.miss = toBuf(missWave());
      this.bufs.done = toBuf(chimeWave());
    }
    if (this.ctx.state === "suspended") this.ctx.resume();
  }

  play(buf, gain, pan) {
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const g = this.ctx.createGain();
    g.gain.value = gain * (store.get("soundVolume") ?? 0.45);
    const panner = this.ctx.createStereoPanner();
    panner.pan.value = pan;
    src.connect(g).connect(panner).connect(this.ctx.destination);
    src.start();
  }

  /** pan: -1(左) 〜 1(右)。打った手の側から聞こえる */
  key(space, pan) {
    const p = store.get("soundPreset");
    if (!p || p === "off") return;
    this.ensure();
    const list = (space ? this.bufs.space : this.bufs.key)[p];
    if (!list) return;
    let i = Math.floor(Math.random() * list.length);
    if (i === this.last && list.length > 1) i = (i + 1) % list.length;
    this.last = i;
    this.play(list[i], (0.85 + Math.random() * 0.15) * (PRESET_GAIN[p] ?? 0.5), pan);
  }

  miss() { this.ensure(); this.play(this.bufs.miss, 0.35, 0); }
  lineDone() { this.ensure(); this.play(this.bufs.done, 0.28, 0); }

  preview() {
    [[0, -0.3], [1, 0.3], [2, -0.1], [3, 0]].forEach(([k, pan]) => setTimeout(() => this.key(k === 3, pan), k * 110));
  }
}
