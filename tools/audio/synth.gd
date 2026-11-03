extends RefCounted
## Offline DSP toolkit used by generate_audio.gd. Every sound of the game is
## synthesised from these primitives (no recorded samples), the same way the
## art is painted by tools/art. Buffers are mono PackedFloat32Array at `rate`.
## Example:
##   var s := Synth.new(32000)
##   var b := s.tone(440.0, 220.0, 0.3, "saw")
##   s.lowpass(b, 1200.0); s.env_perc(b, 0.005, 0.25)

var rate := 32000
var rng := RandomNumberGenerator.new()


func _init(sample_rate: int = 32000, seed_value: int = 1234) -> void:
	rate = sample_rate
	rng.seed = seed_value


func n(seconds: float) -> int:
	return maxi(1, int(seconds * rate))


func silence(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n(seconds))
	return b


# --- Sources --------------------------------------------------------------------------

## Oscillator gliding exponentially from f0 to f1. wave: sine, saw, square, tri.
func tone(f0: float, f1: float, seconds: float, wave: String = "sine", duty: float = 0.5) -> PackedFloat32Array:
	var b := silence(seconds)
	var count := b.size()
	var ph := 0.0
	var inc := f0 / rate
	var k := pow(f1 / maxf(f0, 0.001), 1.0 / count)
	match wave:
		"sine":
			for i in count:
				ph += inc
				inc *= k
				b[i] = sin(ph * TAU)
		"saw":
			for i in count:
				ph += inc
				ph -= floorf(ph)
				inc *= k
				b[i] = 2.0 * ph - 1.0
		"square":
			for i in count:
				ph += inc
				ph -= floorf(ph)
				inc *= k
				b[i] = 1.0 if ph < duty else -1.0
		_:
			for i in count:
				ph += inc
				ph -= floorf(ph)
				inc *= k
				b[i] = 4.0 * absf(ph - 0.5) - 1.0
	return b


## Sum of sines with given frequency ratios / amplitudes / decay times (bells, metal).
## Each decay is the time to fall 60 dB.
func partials(base: float, ratios: Array, amps: Array, decays: Array, seconds: float) -> PackedFloat32Array:
	var b := silence(seconds)
	for k in ratios.size():
		var f: float = base * float(ratios[k])
		if f >= rate * 0.45:
			continue
		var a: float = amps[k]
		var d: float = decays[k]
		var step := TAU * f / rate
		var ph := rng.randf() * TAU
		var g := exp(-6.9 / (maxf(d, 0.001) * rate))
		var e := a
		for i in b.size():
			b[i] += sin(ph) * e
			ph += step
			e *= g
	return b


## White noise (color "white"), or brown-ish ("brown") / pink-ish ("pink").
func noise(seconds: float, color: String = "white") -> PackedFloat32Array:
	var b := silence(seconds)
	var last := 0.0
	var p := [0.0, 0.0, 0.0]
	for i in b.size():
		var w := rng.randf_range(-1.0, 1.0)
		match color:
			"brown":
				last = clampf(last + w * 0.06, -1.0, 1.0) * 0.998
				b[i] = last * 2.5
			"pink":
				p[0] = 0.99765 * p[0] + w * 0.0990460
				p[1] = 0.96300 * p[1] + w * 0.2965164
				p[2] = 0.57000 * p[2] + w * 1.0526913
				b[i] = (p[0] + p[1] + p[2] + w * 0.1848) * 0.25
			_:
				b[i] = w
	return b


## Karplus-Strong plucked string (lute, harp, bow string twang).
func pluck(freq: float, seconds: float, brightness: float = 0.5, decay: float = 0.996) -> PackedFloat32Array:
	var b := silence(seconds)
	var period := maxi(2, int(rate / freq))
	var ring := PackedFloat32Array()
	ring.resize(period)
	var lp := 0.0
	for i in period:
		var w := rng.randf_range(-1.0, 1.0)
		lp = lp + (w - lp) * clampf(brightness, 0.05, 1.0)
		ring[i] = lp
	var idx := 0
	for i in b.size():
		var cur := ring[idx]
		var nxt := ring[(idx + 1) % period]
		var v := (cur + nxt) * 0.5 * decay
		b[i] = cur
		ring[idx] = v
		idx = (idx + 1) % period
	return b


# --- Filters ------------------------------------------------------------------------------

func lowpass(b: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / rate)
	var y := 0.0
	for i in b.size():
		y += (b[i] - y) * a
		b[i] = y
	return b


## Low-pass whose cutoff glides exponentially from c0 to c1 (filter sweeps).
func lowpass_sweep(b: PackedFloat32Array, c0: float, c1: float) -> PackedFloat32Array:
	var y := 0.0
	var y2 := 0.0
	var count := b.size()
	var ratio := c1 / maxf(c0, 1.0)
	for i in count:
		var c := c0 * pow(ratio, float(i) / count)
		var a := 1.0 - exp(-TAU * c / rate)
		y += (b[i] - y) * a
		y2 += (y - y2) * a
		b[i] = y2
	return b


func highpass(b: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / rate)
	var y := 0.0
	for i in b.size():
		y += (b[i] - y) * a
		b[i] = b[i] - y
	return b


## Resonant band-pass (RBJ biquad, constant peak gain).
func bandpass(b: PackedFloat32Array, freq: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * clampf(freq, 20.0, rate * 0.45) / rate
	var alpha := sin(w0) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var b2 := -alpha / a0
	var a1 := -2.0 * cos(w0) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var x := b[i]
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		b[i] = y
	return b


## Vowel formants on a buzzy source ("a", "e", "i", "o", "u", "m").
const VOWELS := {
	"a": [[800, 1.0], [1150, 0.5], [2900, 0.12]],
	"e": [[400, 1.0], [1600, 0.35], [2700, 0.1]],
	"i": [[300, 1.0], [2300, 0.3], [3000, 0.1]],
	"o": [[450, 1.0], [800, 0.45], [2830, 0.08]],
	"u": [[325, 1.0], [700, 0.25], [2530, 0.05]],
	"m": [[250, 1.0], [1000, 0.08], [2200, 0.02]],
}


func formant(src: PackedFloat32Array, vowel: String, shift: float = 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	for fm in VOWELS.get(vowel, VOWELS["a"]):
		var band := bandpass(src.duplicate(), float(fm[0]) * shift, 6.0)
		mix_into(out, band, 0, float(fm[1]))
	return out


## Vowel glide: crossfades two formant sets over the buffer ("y-a", "h-m").
func formant_glide(src: PackedFloat32Array, v0: String, v1: String, shift: float = 1.0) -> PackedFloat32Array:
	var a := formant(src.duplicate(), v0, shift)
	var b := formant(src, v1, shift)
	var count := a.size()
	for i in count:
		var t := float(i) / count
		a[i] = a[i] * (1.0 - t) + b[i] * t
	return a


# --- Envelopes and shaping -------------------------------------------------------------------

## Percussive envelope: linear attack then exponential decay to -60 dB at `decay`.
func env_perc(b: PackedFloat32Array, attack: float, decay: float) -> PackedFloat32Array:
	var na := n(attack)
	var k := log(1000.0) / maxf(decay * rate, 1.0)
	for i in b.size():
		var e := float(i) / na if i < na else exp(-k * (i - na))
		b[i] *= e
	return b


func env_adsr(b: PackedFloat32Array, a: float, d: float, s: float, r: float) -> PackedFloat32Array:
	var count := b.size()
	var na := n(a)
	var nd := n(d)
	var nr := n(r)
	for i in count:
		var e := s
		if i < na:
			e = float(i) / na
		elif i < na + nd:
			e = lerpf(1.0, s, float(i - na) / nd)
		if i > count - nr:
			e *= float(count - i) / nr
		b[i] *= e
	return b


func fade(b: PackedFloat32Array, fin: float, fout: float) -> PackedFloat32Array:
	var ni := n(fin)
	var no := n(fout)
	var count := b.size()
	for i in mini(ni, count):
		b[i] *= float(i) / ni
	for i in mini(no, count):
		b[count - 1 - i] *= float(i) / no
	return b


func gain(b: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in b.size():
		b[i] *= g
	return b


func drive(b: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var norm := 1.0 / tanh(amount)
	for i in b.size():
		b[i] = tanh(b[i] * amount) * norm
	return b


## Amplitude modulation (tremolo, flutter, engines).
func tremolo(b: PackedFloat32Array, freq: float, depth: float) -> PackedFloat32Array:
	for i in b.size():
		b[i] *= 1.0 - depth * (0.5 + 0.5 * sin(TAU * freq * i / rate))
	return b


func normalize(b: PackedFloat32Array, peak: float = 0.9) -> PackedFloat32Array:
	var m := 0.0
	for v in b:
		m = maxf(m, absf(v))
	if m > 0.00001:
		gain(b, peak / m)
	return b


func reverse(b: PackedFloat32Array) -> PackedFloat32Array:
	var out := b.duplicate()
	out.reverse()
	return out


# --- Mixing -----------------------------------------------------------------------------------

## Adds `src` into `dst` starting at sample `offset` (grows nothing; clips at the end).
func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int, g: float = 1.0) -> void:
	var end := mini(dst.size(), offset + src.size())
	for i in range(maxi(offset, 0), end):
		dst[i] += src[i - offset] * g


## Concatenation of buffers with a gap of `gap` seconds.
func join(parts: Array, gap: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
		if gap > 0.0:
			out.append_array(silence(gap))
	return out


## Mixes a list of [buffer, offset_seconds, gain] into one buffer long enough for all.
func layer(items: Array) -> PackedFloat32Array:
	var length := 1
	for it in items:
		length = maxi(length, n(float(it[1])) + (it[0] as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(length)
	for it in items:
		mix_into(out, it[0], n(float(it[1])), float(it[2]) if it.size() > 2 else 1.0)
	return out


## Small Schroeder reverb (4 combs + 2 allpasses). Appends a tail of `tail` seconds.
func reverb(b: PackedFloat32Array, room: float = 0.7, wet: float = 0.25, tail: float = 0.6) -> PackedFloat32Array:
	var out := b.duplicate()
	out.append_array(silence(tail))
	var dry := out.duplicate()
	var wet_buf := PackedFloat32Array()
	wet_buf.resize(out.size())
	var scale := float(rate) / 44100.0
	for d in [1557, 1617, 1491, 1422]:
		var len := maxi(8, int(d * scale))
		var line := PackedFloat32Array()
		line.resize(len)
		var idx := 0
		var damp := 0.0
		for i in out.size():
			var y := line[idx]
			damp = y * 0.6 + damp * 0.4
			line[idx] = dry[i] + damp * room * 0.98
			wet_buf[i] += y * 0.25
			idx = (idx + 1) % len
	for d in [556, 441]:
		var len2 := maxi(4, int(d * scale))
		var buf := PackedFloat32Array()
		buf.resize(len2)
		var j := 0
		for i in wet_buf.size():
			var bo := buf[j]
			var x := wet_buf[i]
			buf[j] = x + bo * 0.5
			wet_buf[i] = bo - x
			j = (j + 1) % len2
	for i in out.size():
		out[i] = dry[i] * (1.0 - wet * 0.5) + wet_buf[i] * wet
	return out


## Seamless loop: crossfades the last `xfade` seconds into the start.
func make_loop(b: PackedFloat32Array, xfade: float) -> PackedFloat32Array:
	var nx := mini(n(xfade), b.size() / 2)
	var body := b.slice(0, b.size() - nx)
	for i in nx:
		var t := float(i) / nx
		body[i] = body[i] * t + b[b.size() - nx + i] * (1.0 - t)
	return body


# --- Output -----------------------------------------------------------------------------------

## Writes a 16-bit mono PCM WAV file.
func save_wav(b: PackedFloat32Array, path: String) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var count := b.size()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + count * 2)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(rate)
	f.store_32(rate * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(count * 2)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for i in count:
		pcm.encode_s16(i * 2, clampi(int(b[i] * 32767.0), -32768, 32767))
	f.store_buffer(pcm)
	f.close()
	return OK
