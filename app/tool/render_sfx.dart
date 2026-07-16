// ignore_for_file: avoid_print — command-line tool, stdout is the UI.
//
// Offline SFX renderer for Trude.
//
// Pure Dart (dart:io + dart:math + dart:typed_data). Synthesizes 16-bit mono
// PCM and writes canonical WAV files into assets/audio/, following the shared
// naming convention `<cueName>_<n>.wav` (cue name exactly as the SfxCue enum
// value, variants numbered from 1).
//
// Run from the app directory:
//   dart run tool/render_sfx.dart
//
// Deterministic: each (cue, variant) pair derives a fixed FNV-1a seed from the
// string "<cueName>#<variant>", so re-running reproduces identical bytes.
//
// Aesthetic bar (from the plan): parlor-quiet, warm, never shrill; every
// one-shot < 4s (most < 0.8s); peak amplitude <= 0.5 so overlapping cues can
// never clip. Bright transient cues render at 44.1 kHz; long, dark, low-passed
// cues render at 22.05 kHz to keep the whole lane under ~1.5 MB (their content
// sits far below the 11 kHz Nyquist, and playback-rate jitter at play time is
// rate-agnostic).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const int kSrBright = 44100; // crisp transients
const int kSrWarm = 22050; // long / low-passed material

// ---------------------------------------------------------------------------
// Deterministic RNG
// ---------------------------------------------------------------------------

int fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h;
}

class Rng {
  Rng(int seed) : _r = Random(seed);
  final Random _r;

  double next() => _r.nextDouble();
  double range(double a, double b) => a + (b - a) * _r.nextDouble();

  /// Bipolar: uniform in [-amt, +amt].
  double bi(double amt) => (_r.nextDouble() * 2 - 1) * amt;

  /// Multiplicative jitter factor around 1.0, e.g. jitter(0.05) -> 0.95..1.05.
  double jitter(double amt) => 1.0 + bi(amt);
}

// ---------------------------------------------------------------------------
// DSP helpers
// ---------------------------------------------------------------------------

double xpow(double a, double b) => pow(a, b).toDouble();

Float64List silence(double seconds, int sr) =>
    Float64List((seconds * sr).round());

enum Wave { sine, triangle, square, saw }

/// Phase-accumulating oscillator; [freq] may vary over time (glides).
Float64List oscBuf(Wave wave, double seconds, int sr, double Function(double t) freq,
    {double phase = 0}) {
  final out = silence(seconds, sr);
  var ph = phase;
  for (var i = 0; i < out.length; i++) {
    final t = i / sr;
    ph += freq(t) / sr;
    final p = ph - ph.floorToDouble();
    out[i] = switch (wave) {
      Wave.sine => sin(2 * pi * p),
      Wave.triangle => 1.0 - 4.0 * (p - 0.5).abs(),
      Wave.square => p < 0.5 ? 1.0 : -1.0,
      Wave.saw => 2.0 * p - 1.0,
    };
  }
  return out;
}

Float64List whiteNoise(double seconds, int sr, Rng rng) {
  final out = silence(seconds, sr);
  for (var i = 0; i < out.length; i++) {
    out[i] = rng.bi(1.0);
  }
  return out;
}

/// Pink-ish noise (Paul Kellet economy filter over white noise).
Float64List pinkNoise(double seconds, int sr, Rng rng) {
  final out = silence(seconds, sr);
  var b0 = 0.0, b1 = 0.0, b2 = 0.0;
  for (var i = 0; i < out.length; i++) {
    final w = rng.bi(1.0);
    b0 = 0.99765 * b0 + w * 0.0990460;
    b1 = 0.96300 * b1 + w * 0.2965164;
    b2 = 0.57000 * b2 + w * 1.0526913;
    out[i] = (b0 + b1 + b2 + w * 0.1848) * 0.2;
  }
  return out;
}

/// In-place one-pole low-pass with (optionally) time-varying cutoff.
void onePoleLP(Float64List x, int sr, double Function(double t) cutoff) {
  var y = 0.0;
  for (var i = 0; i < x.length; i++) {
    final c = cutoff(i / sr);
    final a = 1 - exp(-2 * pi * c / sr);
    y += a * (x[i] - y);
    x[i] = y;
  }
}

/// In-place one-pole high-pass (input minus the low-passed signal).
void onePoleHP(Float64List x, int sr, double Function(double t) cutoff) {
  var y = 0.0;
  for (var i = 0; i < x.length; i++) {
    final c = cutoff(i / sr);
    final a = 1 - exp(-2 * pi * c / sr);
    y += a * (x[i] - y);
    x[i] = x[i] - y;
  }
}

/// Multiply the buffer by an envelope function of time.
void applyEnv(Float64List x, int sr, double Function(double t) env) {
  for (var i = 0; i < x.length; i++) {
    x[i] *= env(i / sr);
  }
}

/// Percussive envelope: linear attack over [a], then exponential decay with
/// time constant [d] (drops to ~5% after 3*d).
double percEnv(double t, double a, double d) {
  if (t < 0) return 0;
  if (t < a) return t / a;
  return exp(-(t - a) / d);
}

/// Mix [src] into [dst] starting at [at] seconds, scaled by [gain].
void mixAt(Float64List dst, Float64List src, double at, int sr,
    {double gain = 1.0}) {
  final off = (at * sr).round();
  for (var i = 0; i < src.length; i++) {
    final j = off + i;
    if (j < 0 || j >= dst.length) continue;
    dst[j] += src[i] * gain;
  }
}

/// Remove DC / very-low drift (one-pole DC blocker, ~15 Hz corner).
void dcBlock(Float64List x, int sr) {
  final r = 1 - 2 * pi * 15 / sr;
  var px = 0.0, py = 0.0;
  for (var i = 0; i < x.length; i++) {
    final y = x[i] - px + r * py;
    px = x[i];
    py = y;
    x[i] = y;
  }
}

/// Short linear fades at both ends so no cue starts or stops with a click.
void fadeEdges(Float64List x, int sr,
    {double fadeIn = 0.002, double fadeOut = 0.012}) {
  final nIn = min(x.length, (fadeIn * sr).round());
  final nOut = min(x.length, (fadeOut * sr).round());
  for (var i = 0; i < nIn; i++) {
    x[i] *= i / nIn;
  }
  for (var i = 0; i < nOut; i++) {
    x[x.length - 1 - i] *= i / nOut;
  }
}

/// Clipping guard: scale so the peak is exactly [peak] (<= 0.5 everywhere).
void normalizeTo(Float64List x, double peak) {
  var m = 0.0;
  for (final v in x) {
    m = max(m, v.abs());
  }
  if (m < 1e-9) return;
  final g = peak / m;
  for (var i = 0; i < x.length; i++) {
    x[i] *= g;
  }
}

// ---------------------------------------------------------------------------
// WAV encode / decode
// ---------------------------------------------------------------------------

Uint8List wavBytes(Float64List x, int sr) {
  final n = x.length;
  final b = ByteData(44 + n * 2);
  void tag(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, sr, Endian.little);
  b.setUint32(28, sr * 2, Endian.little); // byte rate
  b.setUint16(32, 2, Endian.little); // block align
  b.setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setInt16(44 + i * 2, (x[i] * 32767).round().clamp(-32768, 32767),
        Endian.little);
  }
  return b.buffer.asUint8List();
}

class WavInfo {
  WavInfo(this.sampleRate, this.samples);
  final int sampleRate;
  final Float64List samples;
  double get duration => samples.length / sampleRate;
}

WavInfo decodeWav(Uint8List bytes) {
  final b = ByteData.sublistView(bytes);
  String tag(int off) => String.fromCharCodes(bytes.sublist(off, off + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE' || tag(12) != 'fmt ') {
    throw StateError('bad WAV header');
  }
  if (b.getUint32(4, Endian.little) != bytes.length - 8) {
    throw StateError('RIFF size mismatch');
  }
  if (b.getUint16(20, Endian.little) != 1 ||
      b.getUint16(22, Endian.little) != 1 ||
      b.getUint16(34, Endian.little) != 16) {
    throw StateError('expected 16-bit mono PCM');
  }
  final sr = b.getUint32(24, Endian.little);
  if (tag(36) != 'data') throw StateError('missing data chunk');
  final dataLen = b.getUint32(40, Endian.little);
  if (dataLen != bytes.length - 44) throw StateError('data size mismatch');
  final n = dataLen ~/ 2;
  final samples = Float64List(n);
  for (var i = 0; i < n; i++) {
    samples[i] = b.getInt16(44 + i * 2, Endian.little) / 32767.0;
  }
  return WavInfo(sr, samples);
}

// ---------------------------------------------------------------------------
// Cue renderers
// ---------------------------------------------------------------------------

/// Low 80-ish Hz thud + short noise snap. A confident stamp on the table.
Float64List renderClaimStamp(Rng rng, int sr) {
  const dur = 0.34;
  final out = silence(dur, sr);
  final f0 = 118.0 * rng.jitter(0.06);
  final f1 = 70.0 * rng.jitter(0.06);
  final thud =
      oscBuf(Wave.sine, 0.30, sr, (t) => f0 + (f1 - f0) * min(1.0, t / 0.09));
  applyEnv(thud, sr, (t) => percEnv(t, 0.004, 0.10));
  onePoleLP(thud, sr, (_) => 420);
  final snap = whiteNoise(0.06, sr, rng);
  onePoleHP(snap, sr, (_) => 1400);
  onePoleLP(snap, sr, (_) => 6000);
  applyEnv(snap, sr, (t) => percEnv(t, 0.0015, 0.02));
  mixAt(out, thud, 0.0, sr);
  mixAt(out, snap, 0.002, sr, gain: 0.5 * rng.jitter(0.15));
  return out;
}

/// ~3.5s quiet riser: detuned low saws gliding 55 -> 110 Hz through an
/// opening low-pass, with a faint pink-noise bed. Gentle, parlor-quiet.
Float64List renderRevealTension(Rng rng, int sr) {
  const dur = 3.5;
  final out = silence(dur, sr);
  final fA = 55.0 * rng.jitter(0.03);
  final fB = 110.0 * rng.jitter(0.03);
  double freq(double t) => fA * xpow(fB / fA, t / dur);
  final tone = silence(dur, sr);
  mixAt(tone, oscBuf(Wave.saw, dur, sr, freq), 0, sr, gain: 0.5);
  mixAt(tone, oscBuf(Wave.saw, dur, sr, (t) => freq(t) * 1.004), 0, sr,
      gain: 0.5);
  onePoleLP(tone, sr, (t) => 180 + (1200 - 180) * xpow(t / dur, 1.6));
  onePoleLP(tone, sr, (t) => 260 + (2200 - 260) * xpow(t / dur, 1.6));
  final sub = oscBuf(Wave.sine, dur, sr, (t) => freq(t) * 0.5);
  final bed = pinkNoise(dur, sr, rng);
  onePoleLP(bed, sr, (_) => 700);
  mixAt(out, tone, 0, sr);
  mixAt(out, sub, 0, sr, gain: 0.35);
  mixAt(out, bed, 0, sr, gain: 0.06);
  applyEnv(out, sr, (t) {
    final rise = 0.12 + 0.88 * xpow(t / dur, 1.4);
    final tail = t > dur - 0.18 ? max(0.0, (dur - t) / 0.18) : 1.0;
    return rise * tail;
  });
  return out;
}

/// Warm major-third chime: two soft triangles, slightly arpeggiated.
Float64List renderVerdictTruth(Rng rng, int sr) {
  const dur = 0.9;
  final out = silence(dur, sr);
  final root = 523.25 * rng.jitter(0.04);
  final third = root * 1.2599; // major third
  final a = oscBuf(Wave.triangle, 0.8, sr, (_) => root);
  applyEnv(a, sr, (t) => percEnv(t, 0.006, 0.22));
  final b = oscBuf(Wave.triangle, 0.7, sr, (_) => third);
  applyEnv(b, sr, (t) => percEnv(t, 0.006, 0.20));
  final warm = oscBuf(Wave.sine, 0.8, sr, (_) => root / 2);
  applyEnv(warm, sr, (t) => percEnv(t, 0.01, 0.26));
  mixAt(out, a, 0.0, sr, gain: 0.9);
  mixAt(out, b, 0.07 * rng.jitter(0.2), sr, gain: 0.75);
  mixAt(out, warm, 0.0, sr, gain: 0.35);
  onePoleLP(out, sr, (_) => 3800);
  return out;
}

/// Dissonant minor-second stab + soft noise splat. Dramatic, not harsh.
Float64List renderVerdictLie(Rng rng, int sr) {
  const dur = 0.9;
  final out = silence(dur, sr);
  final f = 220.0 * rng.jitter(0.05);
  Float64List stabTone(double base) {
    final tone = silence(0.8, sr);
    double bend(double t) => base * (1 - 0.06 * t / 0.8); // slow wilt
    mixAt(tone, oscBuf(Wave.saw, 0.8, sr, bend), 0, sr, gain: 0.6);
    mixAt(tone, oscBuf(Wave.triangle, 0.8, sr, bend), 0, sr, gain: 0.4);
    applyEnv(tone, sr, (t) => percEnv(t, 0.004, 0.28));
    return tone;
  }

  mixAt(out, stabTone(f), 0, sr, gain: 0.7);
  mixAt(out, stabTone(f * 1.0595), 0, sr, gain: 0.7); // minor second
  final splat = pinkNoise(0.3, sr, rng);
  onePoleLP(splat, sr, (t) => 2000 - 1400 * min(1.0, t / 0.25));
  applyEnv(splat, sr, (t) => percEnv(t, 0.002, 0.07));
  mixAt(out, splat, 0.0, sr, gain: 0.9 * rng.jitter(0.15));
  final thump = oscBuf(Wave.sine, 0.25, sr, (_) => 90.0 * rng.jitter(0.05));
  applyEnv(thump, sr, (t) => percEnv(t, 0.004, 0.09));
  mixAt(out, thump, 0.0, sr, gain: 0.5);
  onePoleLP(out, sr, (_) => 2600);
  return out;
}

/// 12 accelerating ticks rising in pitch over ~1.2s (sweeping up a pile).
Float64List renderPilePickup(Rng rng, int sr) {
  const dur = 1.25;
  const n = 12;
  const usable = 1.02; // ticks span; the rest is tail room
  const r = 0.85; // each gap shrinks to 85% of the previous
  final out = silence(dur, sr);
  final i0 = usable * (1 - r) / (1 - xpow(r, (n - 1).toDouble()));
  var t = 0.02;
  for (var k = 0; k < n; k++) {
    final fk = 340.0 * xpow(2, 0.75 * k / (n - 1)) * rng.jitter(0.03);
    final blip = oscBuf(Wave.sine, 0.045, sr, (_) => fk);
    applyEnv(blip, sr, (tt) => percEnv(tt, 0.0012, 0.016));
    final tap = whiteNoise(0.02, sr, rng);
    onePoleLP(tap, sr, (_) => 2500);
    applyEnv(tap, sr, (tt) => percEnv(tt, 0.001, 0.006));
    final g = 0.65 + 0.35 * k / (n - 1);
    mixAt(out, blip, t, sr, gain: g);
    mixAt(out, tap, t, sr, gain: 0.25 * g);
    t += i0 * xpow(r, k.toDouble()) * rng.jitter(0.06);
  }
  return out;
}

/// Rising 4-note arpeggio, mellow square through a low-pass. Quiet triumph.
Float64List renderQuadFanfare(Rng rng, int sr) {
  const dur = 1.25;
  final out = silence(dur, sr);
  final key = 261.63 * xpow(2, rng.range(-2, 2) / 12);
  const ratios = [1.0, 1.2599, 1.4983, 2.0]; // 1-3-5-8
  const starts = [0.0, 0.2, 0.4, 0.6];
  const decays = [0.14, 0.14, 0.14, 0.34];
  for (var k = 0; k < 4; k++) {
    final f = key * ratios[k];
    final len = k == 3 ? 0.62 : 0.34;
    final note = silence(len, sr);
    mixAt(note, oscBuf(Wave.square, len, sr, (_) => f), 0, sr, gain: 0.55);
    mixAt(note, oscBuf(Wave.square, len, sr, (_) => f * 1.005), 0, sr,
        gain: 0.45);
    onePoleLP(note, sr, (_) => 1300);
    applyEnv(note, sr, (t) => percEnv(t, 0.012, decays[k]));
    mixAt(out, note, starts[k] + rng.bi(0.012), sr,
        gain: k == 3 ? 1.0 : 0.85);
    if (k == 3) {
      final sub = oscBuf(Wave.sine, len, sr, (_) => f / 2);
      applyEnv(sub, sr, (t) => percEnv(t, 0.015, 0.3));
      mixAt(out, sub, starts[k], sr, gain: 0.3);
    }
  }
  return out;
}

/// Tragicomic slow descending tritone sting with growing vibrato and a
/// final pitch droop. "Wah-waah", kept mellow.
Float64List renderJokerReveal(Rng rng, int sr) {
  const dur = 1.7;
  final f1 = 329.63 * xpow(2, rng.range(-1, 1) / 12);
  final f2 = f1 / 1.4142; // tritone below
  final vibRate = 5.2 * rng.jitter(0.1);
  double freq(double t) {
    double base;
    if (t < 0.5) {
      base = f1;
    } else if (t < 0.68) {
      base = f1 * xpow(f2 / f1, (t - 0.5) / 0.18);
    } else {
      base = f2;
    }
    if (t > dur - 0.35) {
      base *= 1 - 0.07 * (t - (dur - 0.35)) / 0.35; // sad final droop
    }
    final depth = t < 0.68 ? 0.004 : 0.004 + 0.022 * min(1.0, (t - 0.68) / 0.6);
    return base * (1 + depth * sin(2 * pi * vibRate * t));
  }

  final out = silence(dur, sr);
  mixAt(out, oscBuf(Wave.triangle, dur, sr, freq), 0, sr, gain: 0.65);
  mixAt(out, oscBuf(Wave.saw, dur, sr, freq), 0, sr, gain: 0.35);
  onePoleLP(out, sr, (t) => 1900 - (1900 - 750) * t / dur);
  applyEnv(out, sr,
      (t) => t < 0.75 ? min(1.0, t / 0.02) : exp(-(t - 0.75) / 0.35));
  return out;
}

/// Soft two-note sine ding. GENTLE: heard every single turn.
Float64List renderYourTurn(Rng rng, int sr) {
  const dur = 0.62;
  final out = silence(dur, sr);
  final f1 = 659.26 * rng.jitter(0.04);
  final interval = rng.next() < 0.5 ? 1.3348 : 1.4983; // fourth or fifth up
  final f2 = f1 * interval;
  Float64List ding(double f, double d) {
    final x = oscBuf(Wave.sine, 0.42, sr, (_) => f);
    applyEnv(x, sr, (t) => percEnv(t, 0.008, d));
    return x;
  }

  mixAt(out, ding(f1, 0.16), 0.0, sr, gain: 0.8);
  mixAt(out, ding(f2, 0.19), 0.18, sr, gain: 0.9);
  final warm = oscBuf(Wave.sine, 0.5, sr, (_) => f1 / 2);
  applyEnv(warm, sr, (t) => percEnv(t, 0.01, 0.2));
  mixAt(out, warm, 0.0, sr, gain: 0.3);
  onePoleLP(out, sr, (_) => 3000);
  return out;
}

/// Single muted woodblock tick, ~0.15s.
Float64List renderTimerUrgent(Rng rng, int sr) {
  const dur = 0.16;
  final out = silence(dur, sr);
  final fMain = 820.0 * rng.jitter(0.05);
  final main = oscBuf(
      Wave.sine, 0.12, sr, (t) => fMain * (1.06 - 0.06 * min(1.0, t / 0.02)));
  applyEnv(main, sr, (t) => percEnv(t, 0.0012, 0.03));
  final hi = oscBuf(Wave.sine, 0.08, sr, (_) => fMain * 1.52);
  applyEnv(hi, sr, (t) => percEnv(t, 0.001, 0.02));
  final click = whiteNoise(0.014, sr, rng);
  onePoleLP(click, sr, (_) => 2800);
  applyEnv(click, sr, (t) => percEnv(t, 0.0008, 0.004));
  mixAt(out, main, 0.0, sr);
  mixAt(out, hi, 0.0, sr, gain: 0.45);
  mixAt(out, click, 0.0, sr, gain: 0.4);
  onePoleLP(out, sr, (_) => 2600); // muted
  return out;
}

/// Short pitched cartoon pop, ~0.2s.
Float64List renderReactionPop(Rng rng, int sr) {
  const dur = 0.22;
  final out = silence(dur, sr);
  final f0 = 950.0 * rng.jitter(0.08);
  final f1 = 320.0 * rng.jitter(0.08);
  final body = oscBuf(
      Wave.sine, 0.16, sr, (t) => f0 * xpow(f1 / f0, min(1.0, t / 0.09)));
  applyEnv(body, sr, (t) => percEnv(t, 0.002, 0.05));
  final burst = whiteNoise(0.012, sr, rng);
  onePoleLP(burst, sr, (_) => 4000);
  applyEnv(burst, sr, (t) => percEnv(t, 0.0008, 0.003));
  mixAt(out, body, 0.0, sr);
  mixAt(out, burst, 0.0, sr, gain: 0.3);
  return out;
}

/// Tiny felt-muted click, ~0.06s, very quiet (fires on every button press).
Float64List renderUiTap(Rng rng, int sr) {
  const dur = 0.06;
  final out = silence(dur, sr);
  final click = whiteNoise(0.028, sr, rng);
  onePoleLP(click, sr, (_) => 1300);
  applyEnv(click, sr, (t) => percEnv(t, 0.001, 0.008));
  final thump = oscBuf(Wave.sine, 0.035, sr, (_) => 190.0 * rng.jitter(0.08));
  applyEnv(thump, sr, (t) => percEnv(t, 0.0015, 0.012));
  mixAt(out, click, 0.0, sr);
  mixAt(out, thump, 0.0, sr, gain: 0.6);
  return out;
}

// --- Synth fallbacks for the card-sample cues (overwritten if real samples
// --- from the CC0 pack land; same naming convention).

/// 0.7s card riffle: dense band-passed noise flutter.
Float64List renderShuffle(Rng rng, int sr) {
  const dur = 0.72;
  final noise = whiteNoise(dur, sr, rng);
  onePoleHP(noise, sr, (_) => 900);
  onePoleLP(noise, sr, (_) => 4800);
  // Flutter: a train of short pulses, slightly accelerating, with jitter.
  final flutter = silence(dur, sr);
  var t = 0.02;
  var gap = 0.030;
  while (t < dur - 0.06) {
    final g = rng.range(0.55, 1.0);
    final n0 = (t * sr).round();
    for (var i = 0; i < (0.012 * sr).round(); i++) {
      final j = n0 + i;
      if (j >= flutter.length) break;
      flutter[j] = max(flutter[j], g * percEnv(i / sr, 0.001, 0.0035));
    }
    t += gap * rng.jitter(0.25);
    gap = max(0.017, gap * 0.985); // gentle acceleration
  }
  for (var i = 0; i < noise.length; i++) {
    noise[i] *= flutter[i];
  }
  final bed = pinkNoise(dur, sr, rng);
  onePoleLP(bed, sr, (_) => 500);
  final out = silence(dur, sr);
  mixAt(out, noise, 0, sr);
  mixAt(out, bed, 0, sr, gain: 0.10);
  applyEnv(out, sr, (tt) {
    final a = min(1.0, tt / 0.05);
    final rel = tt > dur - 0.12 ? max(0.0, (dur - tt) / 0.12) : 1.0;
    return a * rel;
  });
  return out;
}

/// 0.18s airy noise swish with falling band.
Float64List renderCardThrow(Rng rng, int sr) {
  const dur = 0.18;
  final out = whiteNoise(dur, sr, rng);
  final j = rng.jitter(0.1);
  onePoleHP(out, sr, (t) => (1800 - 1300 * min(1.0, t / dur)) * j);
  onePoleLP(out, sr, (t) => (4500 - 3100 * min(1.0, t / dur)) * j);
  applyEnv(out, sr, (t) {
    if (t < 0.05) return t / 0.05;
    return xpow(max(0.0, 1 - (t - 0.05) / (dur - 0.05)), 1.3);
  });
  return out;
}

/// 0.09s soft felt tap.
Float64List renderCardLand(Rng rng, int sr) {
  const dur = 0.09;
  final out = silence(dur, sr);
  final tap = whiteNoise(0.045, sr, rng);
  onePoleLP(tap, sr, (_) => 900.0 * rng.jitter(0.1));
  applyEnv(tap, sr, (t) => percEnv(t, 0.0015, 0.012));
  final thump = oscBuf(Wave.sine, 0.05, sr, (_) => 140.0 * rng.jitter(0.08));
  applyEnv(thump, sr, (t) => percEnv(t, 0.002, 0.018));
  mixAt(out, tap, 0.0, sr);
  mixAt(out, thump, 0.0, sr, gain: 0.7);
  return out;
}

/// 0.4s slower, softer swish.
Float64List renderCardSlide(Rng rng, int sr) {
  const dur = 0.42;
  final out = pinkNoise(dur, sr, rng);
  final j = rng.jitter(0.1);
  onePoleHP(out, sr, (_) => 300);
  onePoleLP(out, sr, (t) => (2400 - 1700 * min(1.0, t / dur)) * j);
  // Subtle texture flutter so it reads as card-on-felt, not wind.
  final fl = 14.0 * rng.jitter(0.15);
  applyEnv(out, sr, (t) => 1 + 0.18 * sin(2 * pi * fl * t));
  applyEnv(out, sr, (t) {
    if (t < 0.12) return xpow(t / 0.12, 1.2);
    return xpow(max(0.0, 1 - (t - 0.12) / (dur - 0.12)), 1.4);
  });
  return out;
}

/// 0.07s sharp flip snap.
Float64List renderFlipSnap(Rng rng, int sr) {
  const dur = 0.07;
  final out = silence(dur, sr);
  final snap = whiteNoise(0.02, sr, rng);
  onePoleHP(snap, sr, (_) => 2200);
  applyEnv(snap, sr, (t) => percEnv(t, 0.0008, 0.005));
  final f0 = 480.0 * rng.jitter(0.1);
  final blip =
      oscBuf(Wave.sine, 0.03, sr, (t) => f0 * (1 - 0.45 * min(1.0, t / 0.02)));
  applyEnv(blip, sr, (t) => percEnv(t, 0.001, 0.009));
  mixAt(out, snap, 0.0, sr);
  mixAt(out, blip, 0.0, sr, gain: 0.5);
  return out;
}

// ---------------------------------------------------------------------------
// Cue table + main
// ---------------------------------------------------------------------------

class CueSpec {
  const CueSpec(this.name, this.variants, this.sampleRate, this.targetPeak,
      this.render);
  final String name; // exactly the SfxCue enum value
  final int variants;
  final int sampleRate;
  final double targetPeak; // final normalized peak, always <= 0.5
  final Float64List Function(Rng rng, int sr) render;
}

const double kMaxPeak = 0.5;

final List<CueSpec> kCues = [
  // Dramatic synthesized cues.
  CueSpec('claimStamp', 3, kSrBright, 0.50, renderClaimStamp),
  CueSpec('revealTension', 2, kSrWarm, 0.28, renderRevealTension),
  CueSpec('verdictTruth', 2, kSrWarm, 0.40, renderVerdictTruth),
  CueSpec('verdictLie', 2, kSrWarm, 0.50, renderVerdictLie),
  CueSpec('pilePickup', 2, kSrWarm, 0.45, renderPilePickup),
  CueSpec('quadFanfare', 2, kSrWarm, 0.45, renderQuadFanfare),
  CueSpec('jokerReveal', 2, kSrWarm, 0.42, renderJokerReveal),
  CueSpec('yourTurn', 2, kSrWarm, 0.30, renderYourTurn),
  CueSpec('timerUrgent', 3, kSrBright, 0.40, renderTimerUrgent),
  CueSpec('reactionPop', 3, kSrBright, 0.45, renderReactionPop),
  CueSpec('uiTap', 3, kSrBright, 0.10, renderUiTap),
  // Synth fallbacks for the card-sample cues.
  CueSpec('shuffle', 2, kSrWarm, 0.40, renderShuffle),
  CueSpec('cardThrow', 3, kSrBright, 0.35, renderCardThrow),
  CueSpec('cardLand', 3, kSrBright, 0.40, renderCardLand),
  CueSpec('cardSlide', 3, kSrWarm, 0.30, renderCardSlide),
  CueSpec('flipSnap', 3, kSrBright, 0.50, renderFlipSnap),
];

Directory resolveOutDir() {
  var appDir = Directory.current;
  if (!File('${appDir.path}${Platform.pathSeparator}pubspec.yaml')
      .existsSync()) {
    // Fall back to the script's location: tool/render_sfx.dart -> app dir.
    final script = File.fromUri(Platform.script);
    appDir = script.parent.parent;
  }
  final out = Directory(
      '${appDir.path}${Platform.pathSeparator}assets${Platform.pathSeparator}audio');
  out.createSync(recursive: true);
  return out;
}

void main() {
  final outDir = resolveOutDir();
  final written = <String>[];

  for (final cue in kCues) {
    for (var v = 1; v <= cue.variants; v++) {
      final rng = Rng(fnv1a('${cue.name}#$v'));
      final samples = cue.render(rng, cue.sampleRate);
      dcBlock(samples, cue.sampleRate);
      fadeEdges(samples, cue.sampleRate);
      normalizeTo(samples, cue.targetPeak);
      final bytes = wavBytes(samples, cue.sampleRate);
      final path = '${outDir.path}${Platform.pathSeparator}${cue.name}_$v.wav';
      File(path).writeAsBytesSync(bytes);
      written.add(path);
    }
  }

  // -------------------------------------------------------------------------
  // Verification: decode every written file back and check it end to end.
  // -------------------------------------------------------------------------
  print('file                  |    sr |  dur(s) |  peak  |    DC    |  bytes');
  print('----------------------+-------+---------+--------+----------+-------');
  var totalBytes = 0;
  var failures = 0;
  for (final path in written) {
    final bytes = File(path).readAsBytesSync();
    totalBytes += bytes.length;
    final name = path.split(Platform.pathSeparator).last;
    try {
      final wav = decodeWav(Uint8List.fromList(bytes));
      var peak = 0.0, sum = 0.0;
      for (final s in wav.samples) {
        peak = max(peak, s.abs());
        sum += s;
      }
      final dc = sum / wav.samples.length;
      final okPeak = peak <= kMaxPeak + 1e-4;
      final okDc = dc.abs() < 0.003;
      final okDur = wav.duration < 4.0;
      if (!okPeak || !okDc || !okDur) failures++;
      print('${name.padRight(22)}| ${wav.sampleRate.toString().padLeft(5)} | '
          '${wav.duration.toStringAsFixed(3).padLeft(7)} | '
          '${peak.toStringAsFixed(3).padLeft(6)} | '
          '${dc.toStringAsExponential(1).padLeft(8)} | '
          '${bytes.length.toString().padLeft(6)}'
          '${okPeak ? '' : '  PEAK>0.5!'}${okDc ? '' : '  DC-DRIFT!'}'
          '${okDur ? '' : '  TOO-LONG!'}');
    } on StateError catch (e) {
      failures++;
      print('${name.padRight(22)}|  INVALID WAV: $e');
    }
  }
  print('----------------------+-------+---------+--------+----------+-------');
  print('${written.length} files, total ${(totalBytes / 1024).toStringAsFixed(1)} KiB '
      '(${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MiB)');
  if (failures > 0) {
    stderr.writeln('FAILED: $failures file(s) violated the checks.');
    exitCode = 1;
  } else {
    print('All checks passed: valid RIFF/WAVE, peak <= 0.5, no DC drift, < 4s.');
  }
}
