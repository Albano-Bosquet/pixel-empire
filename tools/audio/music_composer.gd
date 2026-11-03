extends RefCounted
## Procedural music: composes and renders a full track from a style
## description (key, mode, tempo, chord progression, instruments, drum
## pattern). Melodies follow simple rules (chord tones on strong beats, mostly
## stepwise motion, an A A' B A form ending on the tonic) so tracks sound
## composed rather than random. Rendering is offline (generate_audio.gd).

const Synth := preload("res://tools/audio/synth.gd")

const MODES := {
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"aeolian": [0, 2, 3, 5, 7, 8, 10],
	"ionian": [0, 2, 4, 5, 7, 9, 11],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
	"harmonic": [0, 2, 3, 5, 7, 8, 11],
}

var s: Synth
var rng := RandomNumberGenerator.new()
var _scale: Array = []
var _root := 50
var _beat := 0.7


func _init(synth: Synth) -> void:
	s = synth


static func midi_hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## Scale degree (0-based, may exceed 6 or be negative) -> MIDI note.
func degree(d: int, octave: int = 0) -> int:
	var size := _scale.size()
	var o := floori(float(d) / size)
	return _root + 12 * (o + octave) + int(_scale[posmod(d, size)])


## Renders a track. style keys: root (MIDI), mode, bpm, bars_per_section,
## progression (scale degrees, one chord per bar), lead, bass, pad, arp,
## drums ("frame" | "march" | "war" | "none"), form (Array of section letters),
## seed, swing (0..0.3), density (0..1 melody note density).
func render(style: Dictionary) -> PackedFloat32Array:
	rng.seed = int(style.get("seed", 1))
	s.rng.seed = rng.seed
	_scale = MODES.get(style.get("mode", "dorian"), MODES["dorian"])
	_root = int(style.get("root", 50))
	_beat = 60.0 / float(style.get("bpm", 84))
	var bar := _beat * 4.0
	var prog: Array = style.get("progression", [0, 6, 3, 0])
	var form: Array = style.get("form", ["I", "A", "A2", "B", "A", "O"])
	var bars_sec := prog.size()
	var total_bars := form.size() * bars_sec
	var out := s.silence(total_bars * bar + 3.0)
	var motif_a := _melody(prog, float(style.get("density", 0.6)), 0)
	var motif_b := _melody(prog, float(style.get("density", 0.6)) * 1.1, 2)
	var bar_i := 0
	for sec in form:
		var t0 := bar_i * bar
		var intensity := 0.55 if sec in ["I", "O"] else (1.0 if sec == "B" else 0.85)
		for k in bars_sec:
			var chord_deg: int = prog[k]
			var tb := t0 + k * bar
			if style.get("pad", "") != "":
				_mix(out, _pad_chord(String(style["pad"]), chord_deg, bar), tb, 0.22 * intensity)
			if style.get("bass", "") != "" and sec != "I":
				_bass(out, String(style["bass"]), chord_deg, tb, bar, 0.42 * intensity)
			if style.get("arp", "") != "" and sec != "O":
				_arp(out, String(style["arp"]), chord_deg, tb, bar, 0.2 * intensity, float(style.get("swing", 0.0)))
			if String(style.get("drums", "none")) != "none" and sec != "I":
				_drums(out, String(style["drums"]), tb, intensity, sec == "B")
		if sec in ["A", "A2", "B"]:
			var motif: Array = motif_b if sec == "B" else motif_a
			if sec == "A2":
				motif = _vary(motif_a)
			for nt in motif:
				var start: float = t0 + float(nt[0]) * _beat
				var lead_oct := 1 if sec == "B" else 0
				_lead(out, String(style.get("lead", "flute")), degree(int(nt[1]), 1 + lead_oct), start, float(nt[2]) * _beat, 0.34)
			if style.has("lead2") and sec == "B":
				for nt2 in motif_a:
					_lead(out, String(style["lead2"]), degree(int(nt2[1]) - 2, 1), t0 + float(nt2[0]) * _beat, float(nt2[2]) * _beat, 0.18)
		if sec == "O":
			_lead(out, String(style.get("lead", "flute")), degree(0, 1), t0, bar * 2.0, 0.3)
		bar_i += bars_sec
	s.fade(out, 1.5, 3.0)
	return s.normalize(out, 0.8)


func _mix(out: PackedFloat32Array, b: PackedFloat32Array, t: float, g: float) -> void:
	s.mix_into(out, b, s.n(t), g)


# --- Composition ------------------------------------------------------------------------------

## A melody over the progression: [[beat, degree, length_beats], ...].
## Strong beats land on chord tones; other notes move by step from the last.
func _melody(prog: Array, density: float, lift: int) -> Array:
	var notes := []
	var cur := lift
	for k in prog.size():
		var chord: int = prog[k]
		var beat := 0.0
		while beat < 4.0:
			var strong := fmod(beat, 2.0) < 0.01
			var length := 1.0
			var r := rng.randf()
			if r < density * 0.45:
				length = 0.5
			elif r > 0.85:
				length = 2.0
			if beat + length > 4.0:
				length = 4.0 - beat
			if strong:
				var tones := [chord, chord + 2, chord + 4]
				var best: int = tones[0]
				for c in tones:
					for oct in [-7, 0, 7]:
						if absi(c + oct - cur) < absi(best - cur):
							best = c + oct
				cur = best
			else:
				cur += [-1, 1, 1, -1, 2, -2][rng.randi() % 6]
			cur = clampi(cur, -2, 9)
			if rng.randf() > 0.12 or strong:
				notes.append([k * 4.0 + beat, cur, length])
			beat += length
	# Phrase ending: last note held on the tonic.
	if not notes.is_empty():
		notes[notes.size() - 1][1] = 0 if absi(cur) < 4 else 7
		notes[notes.size() - 1][2] = maxf(1.5, notes[notes.size() - 1][2])
	return notes


## Variation: keeps the rhythm, nudges some inner pitches.
func _vary(motif: Array) -> Array:
	var out := []
	for i in motif.size():
		var nt: Array = motif[i].duplicate()
		if i > 0 and i < motif.size() - 2 and rng.randf() < 0.3:
			nt[1] = int(nt[1]) + (1 if rng.randf() < 0.5 else -1)
		out.append(nt)
	return out


# --- Parts ------------------------------------------------------------------------------------

func _pad_chord(kind: String, chord_deg: int, dur: float) -> PackedFloat32Array:
	var items := []
	for d in [chord_deg, chord_deg + 2, chord_deg + 4]:
		var f := midi_hz(degree(d, 0))
		match kind:
			"choir":
				items.append([_voice_ah(f, dur), 0.0, 0.5])
			"organ":
				items.append([_organ(f, dur), 0.0, 0.5])
			_:
				items.append([_strings(f, dur), 0.0, 0.5])
	return s.layer(items)


func _bass(out: PackedFloat32Array, kind: String, chord_deg: int, tb: float, bar: float, g: float) -> void:
	var f := midi_hz(degree(chord_deg, -2))
	match kind:
		"drone":
			_mix(out, _drone(f, bar), tb, g)
		"pluck":
			_mix(out, s.env_perc(s.pluck(f, bar * 0.5, 0.35, 0.997), 0.002, bar * 0.45), tb, g * 1.2)
			_mix(out, s.env_perc(s.pluck(midi_hz(degree(chord_deg + 4, -2)), bar * 0.5, 0.35, 0.997), 0.002, bar * 0.45), tb + bar * 0.5, g)
		"march":
			for b in 4:
				var deg := chord_deg if b % 2 == 0 else chord_deg + 4
				_mix(out, _brass(midi_hz(degree(deg, -2)), _beat * 0.8, 500.0), tb + b * _beat, g * 0.8)
		_:
			_mix(out, _strings(f, bar), tb, g)


func _arp(out: PackedFloat32Array, kind: String, chord_deg: int, tb: float, bar: float, g: float, swing: float) -> void:
	var pattern := [0, 2, 4, 7, 4, 2, 0, 2]
	for i in 8:
		var t := tb + i * bar / 8.0 + (swing * bar / 8.0 if i % 2 == 1 else 0.0)
		var f := midi_hz(degree(chord_deg + int(pattern[i]), 0))
		match kind:
			"harp":
				_mix(out, s.env_perc(s.pluck(f, 1.2, 0.6, 0.996), 0.002, 1.0), t, g)
			"bell":
				_mix(out, s.partials(f, [1.0, 2.0, 3.0, 4.07], [1.0, 0.3, 0.15, 0.08], [1.0, 0.6, 0.4, 0.2], 1.0), t, g * 0.8)
			_:
				_mix(out, s.env_perc(s.pluck(f, 0.9, 0.45, 0.994), 0.002, 0.8), t, g)


func _lead(out: PackedFloat32Array, kind: String, midi: int, start: float, dur: float, g: float) -> void:
	var f := midi_hz(midi)
	var d := maxf(dur, 0.12)
	match kind:
		"fife":
			_mix(out, _flute(f * 2.0, d * 0.95, 0.06), start, g * 0.7)
		"brass":
			_mix(out, _brass(f, d * 0.95, 2200.0), start, g * 0.8)
		"choir":
			_mix(out, _voice_ah(f, d + 0.2), start, g)
		"lute":
			_mix(out, s.env_perc(s.pluck(f, d + 0.6, 0.6, 0.996), 0.002, d + 0.5), start, g * 1.3)
		"strings":
			_mix(out, _strings(f, d + 0.15), start, g)
		_:
			_mix(out, _flute(f, d * 0.95, 0.12), start, g)


func _drums(out: PackedFloat32Array, kind: String, tb: float, intensity: float, busy: bool) -> void:
	match kind:
		"frame":
			for hit in [[0.0, 1.0, "low"], [1.5, 0.6, "low"], [2.0, 0.8, "low"], [3.0, 0.5, "high"], [3.5, 0.4, "high"]]:
				_mix(out, _frame_drum(String(hit[2])), tb + float(hit[0]) * _beat, float(hit[1]) * 0.5 * intensity)
			if busy:
				for i in 8:
					_mix(out, _shaker(), tb + i * _beat * 0.5, 0.12 * intensity)
		"march":
			for i in 4:
				_mix(out, _snare(), tb + i * _beat, (0.35 if i % 2 == 0 else 0.25) * intensity)
				if busy or i == 3:
					_mix(out, _snare(), tb + (i + 0.75) * _beat, 0.15 * intensity)
			_mix(out, _timpani(55.0), tb, 0.5 * intensity)
		"war":
			for i in 8:
				var accent := i % 4 == 0
				_mix(out, _timpani(50.0 if accent else 62.0), tb + i * _beat * 0.5, (0.55 if accent else 0.28) * intensity)
			for i in 4:
				_mix(out, _snare(), tb + (i + 0.5) * _beat, 0.22 * intensity)
		"modern":
			for i in 4:
				_mix(out, _kick(), tb + i * _beat, 0.5 * intensity)
				_mix(out, _snare(), tb + (i + 0.5) * _beat, (0.25 if i % 2 == 1 else 0.12) * intensity)
				for k in 2:
					_mix(out, _shaker(), tb + (i + k * 0.5) * _beat, 0.08 * intensity)


# --- Instruments ------------------------------------------------------------------------------

func _flute(f: float, dur: float, breath: float) -> PackedFloat32Array:
	var b := s.silence(dur)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / s.rate
		var vib := 1.0 + 0.006 * sin(TAU * 5.2 * t) * clampf((t - 0.15) * 4.0, 0.0, 1.0)
		ph += f * vib / s.rate
		b[i] = sin(ph * TAU) + 0.18 * sin(ph * TAU * 2.0) + 0.05 * sin(ph * TAU * 3.0)
	var air := s.lowpass(s.highpass(s.noise(dur), 1200), 4000)
	s.mix_into(b, air, 0, breath)
	return s.env_adsr(b, 0.06, 0.1, 0.85, minf(0.12, dur * 0.4))


func _strings(f: float, dur: float) -> PackedFloat32Array:
	var b := s.tone(f, f, dur, "saw")
	s.mix_into(b, s.tone(f * 1.006, f * 1.006, dur, "saw"), 0, 0.8)
	s.mix_into(b, s.tone(f * 0.995, f * 0.995, dur, "saw"), 0, 0.6)
	s.lowpass(b, 1400)
	s.lowpass(b, 2400)
	return s.env_adsr(b, minf(0.35, dur * 0.3), 0.2, 0.8, minf(0.4, dur * 0.3))


func _voice_ah(f: float, dur: float) -> PackedFloat32Array:
	var b := s.tone(f, f, dur, "saw")
	s.mix_into(b, s.tone(f * 1.005, f * 1.005, dur, "saw"), 0, 0.7)
	s.tremolo(b, 5.0, 0.1)
	var v := s.formant(b, "a" if f < 300.0 else "o")
	return s.env_adsr(v, minf(0.3, dur * 0.3), 0.1, 0.85, minf(0.35, dur * 0.3))


func _organ(f: float, dur: float) -> PackedFloat32Array:
	var b := s.partials(f, [1.0, 2.0, 3.0, 4.0, 6.0], [1.0, 0.6, 0.35, 0.25, 0.1], [99.0, 99.0, 99.0, 99.0, 99.0], dur)
	return s.env_adsr(b, 0.05, 0.1, 0.9, 0.15)


func _drone(f: float, dur: float) -> PackedFloat32Array:
	var b := s.tone(f, f, dur, "saw")
	s.mix_into(b, s.tone(f * 1.5, f * 1.5, dur, "saw"), 0, 0.5)
	s.lowpass(b, 500)
	return s.env_adsr(b, 0.2, 0.1, 0.9, 0.2)


func _brass(f: float, dur: float, bright: float) -> PackedFloat32Array:
	var b := s.tone(f, f, dur, "saw")
	s.mix_into(b, s.tone(f * 1.003, f * 1.003, dur, "saw"), 0, 0.7)
	s.lowpass_sweep(b, bright * 0.3, bright)
	return s.env_adsr(b, 0.04, 0.12, 0.75, minf(0.12, dur * 0.4))


func _frame_drum(kind: String) -> PackedFloat32Array:
	var f := 95.0 if kind == "low" else 180.0
	var body := s.env_perc(s.tone(f * 1.6, f, 0.35, "sine"), 0.001, 0.3)
	var skin := s.env_perc(s.bandpass(s.noise(0.08), f * 6.0, 1.0), 0.001, 0.06)
	return s.layer([[body, 0.0, 1.0], [skin, 0.0, 0.5]])


func _timpani(f: float) -> PackedFloat32Array:
	var body := s.env_perc(s.tone(f * 1.3, f, 1.0, "sine"), 0.002, 0.9)
	var hit := s.env_perc(s.lowpass(s.noise(0.15, "brown"), 900), 0.001, 0.12)
	return s.layer([[body, 0.0, 1.0], [hit, 0.0, 0.6]])


func _snare() -> PackedFloat32Array:
	var rattle := s.env_perc(s.bandpass(s.noise(0.2), 3000, 0.8), 0.001, 0.15)
	var tone := s.env_perc(s.tone(200, 160, 0.1, "tri"), 0.001, 0.08)
	return s.layer([[rattle, 0.0, 1.0], [tone, 0.0, 0.5]])


func _kick() -> PackedFloat32Array:
	return s.env_perc(s.tone(120, 45, 0.3, "sine"), 0.001, 0.25)


func _shaker() -> PackedFloat32Array:
	return s.env_perc(s.highpass(s.noise(0.06), 5000), 0.003, 0.05)
