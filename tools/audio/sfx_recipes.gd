extends RefCounted
## Sound-effect recipes: every one-shot and loop of the game, built from Synth
## primitives. all() returns {name: PackedFloat32Array}; names are the keys
## used by assets/data/audio.json. Variations of one sound end in _1, _2...

const Synth := preload("res://tools/audio/synth.gd")

var s: Synth


func _init(synth: Synth) -> void:
	s = synth


func all() -> Dictionary:
	var out := {}
	_ui(out)
	_voices(out)
	_combat(out)
	_economy(out)
	_buildings(out)
	_animals(out)
	_ambience(out)
	_extras(out)
	for k in out:
		var looped := String(k).ends_with("_loop") or String(k).begins_with("amb_")
		if not looped:
			s.fade(out[k], 0.0, 0.012)
		s.normalize(out[k], 0.85 if not looped else 0.6)
	return out


# --- Building blocks ---------------------------------------------------------------------------

## A short throaty "voice" syllable: buzzy source through vowel formants.
func voice(pitch: float, v0: String, v1: String, dur: float, shift: float = 1.0, end_pitch: float = -1.0) -> PackedFloat32Array:
	var src := s.tone(pitch, end_pitch if end_pitch > 0.0 else pitch * 0.92, dur, "saw")
	var jitter := s.noise(dur, "pink")
	s.mix_into(src, s.gain(jitter, 0.15), 0)
	var b := s.formant_glide(src, v0, v1, shift)
	return s.env_adsr(b, 0.02, dur * 0.3, 0.7, dur * 0.35)


## Metal impact: inharmonic partials plus a noise click.
func metal(base: float, dur: float, bright: float = 1.0) -> PackedFloat32Array:
	var ring := s.partials(base, [1.0, 2.41, 3.87, 5.13, 7.3], [1.0, 0.6, 0.45, 0.3, 0.2 * bright], [dur, dur * 0.7, dur * 0.5, dur * 0.35, dur * 0.2], dur)
	var click := s.env_perc(s.highpass(s.noise(0.04), 2000.0), 0.0005, 0.03)
	return s.layer([[ring, 0.0, 0.6], [click, 0.0, 0.8]])


## Wooden knock: damped low partials and a filtered click.
func wood(base: float, dur: float) -> PackedFloat32Array:
	var body := s.partials(base, [1.0, 2.3, 3.9], [1.0, 0.5, 0.25], [dur, dur * 0.5, dur * 0.3], dur)
	var click := s.env_perc(s.bandpass(s.noise(0.05), base * 4.0, 1.2), 0.0005, 0.04)
	return s.layer([[body, 0.0, 0.7], [click, 0.0, 1.0]])


## Filtered-noise burst (whooshes, rustles, splashes).
func burst(dur: float, lo: float, hi: float, attack: float = 0.005, color: String = "white") -> PackedFloat32Array:
	var b := s.noise(dur, color)
	s.highpass(b, lo)
	s.lowpass(b, hi)
	return s.env_perc(b, attack, dur)


func whoosh(dur: float, f0: float, f1: float) -> PackedFloat32Array:
	var b := s.noise(dur)
	var out := PackedFloat32Array()
	out.resize(b.size())
	# Band-pass sweep built from short segments.
	var seg := s.n(0.02)
	var i := 0
	while i < b.size():
		var t := float(i) / b.size()
		var part := b.slice(i, mini(i + seg, b.size()))
		s.bandpass(part, lerpf(f0, f1, t), 2.0)
		for k in part.size():
			out[i + k] = part[k]
		i += seg
	return s.env_adsr(out, dur * 0.4, dur * 0.2, 0.6, dur * 0.4)


## Gunshot: sharp noise crack, low thump and a short room tail.
func shot(dur: float, thump: float, bright: float) -> PackedFloat32Array:
	var crack := s.env_perc(s.lowpass(s.noise(dur), bright), 0.0005, dur * 0.4)
	var low := s.env_perc(s.tone(thump, thump * 0.5, dur, "sine"), 0.001, dur * 0.6)
	return s.reverb(s.layer([[crack, 0.0, 1.0], [low, 0.0, 0.8]]), 0.6, 0.25, 0.35)


## Explosion: brown noise rumble with a sweeping low-pass and sub thump.
func explosion(dur: float, size: float) -> PackedFloat32Array:
	var body := s.noise(dur, "brown")
	s.lowpass_sweep(body, 3000.0 * size, 120.0)
	s.env_perc(body, 0.002, dur)
	var sub := s.env_perc(s.tone(70.0 * size, 30.0, dur * 0.7, "sine"), 0.002, dur * 0.6)
	var crack := s.env_perc(s.noise(0.08), 0.0005, 0.06)
	return s.drive(s.layer([[body, 0.0, 1.0], [sub, 0.0, 0.9], [crack, 0.0, 0.5]]), 1.6)


func chime(freqs: Array, step: float, dur: float) -> PackedFloat32Array:
	var items := []
	for i in freqs.size():
		var bell := s.partials(freqs[i], [1.0, 2.0, 3.01, 4.2], [1.0, 0.4, 0.2, 0.08], [dur, dur * 0.6, dur * 0.3, dur * 0.2], dur)
		items.append([bell, i * step, 0.7])
	return s.layer(items)


func horn(freqs: Array, step: float, note_dur: float, last_dur: float) -> PackedFloat32Array:
	var items := []
	for i in freqs.size():
		var d := last_dur if i == freqs.size() - 1 else note_dur
		var b := s.tone(freqs[i], freqs[i], d, "saw")
		s.mix_into(b, s.tone(freqs[i] * 1.004, freqs[i] * 1.004, d, "saw"), 0, 0.6)
		s.lowpass_sweep(b, 600.0, 2400.0)
		s.env_adsr(b, 0.04, 0.1, 0.75, 0.12)
		items.append([b, i * step, 0.6])
	return s.reverb(s.layer(items), 0.75, 0.3, 0.8)


# --- UI --------------------------------------------------------------------------------------------

func _ui(o: Dictionary) -> void:
	o["ui_click"] = s.layer([[wood(900.0, 0.06), 0.0, 0.8], [s.env_perc(s.tone(1800, 1600, 0.04, "sine"), 0.001, 0.03), 0.0, 0.3]])
	o["ui_hover"] = s.env_perc(s.tone(2400, 2300, 0.03, "sine"), 0.001, 0.02)
	o["ui_error"] = s.layer([[s.env_perc(s.lowpass(s.tone(220, 200, 0.18, "square"), 1200), 0.002, 0.15), 0.0, 0.6], [s.env_perc(s.lowpass(s.tone(165, 150, 0.22, "square"), 1000), 0.002, 0.2), 0.09, 0.6]])
	o["ui_place"] = s.layer([[wood(140.0, 0.25), 0.0, 1.0], [burst(0.25, 200, 1500, 0.002, "pink"), 0.01, 0.6]])
	o["ui_cancel"] = s.env_perc(s.tone(700, 400, 0.1, "tri"), 0.002, 0.09)
	o["ui_queue"] = s.layer([[wood(600.0, 0.08), 0.0, 0.8], [s.env_perc(s.tone(1200, 1250, 0.06, "sine"), 0.002, 0.05), 0.02, 0.3]])
	o["notify"] = chime([1046.5, 1318.5], 0.08, 0.6)
	o["chat"] = chime([1568.0], 0.0, 0.35)
	o["research_done"] = chime([784.0, 987.8, 1174.7, 1568.0], 0.09, 1.0)
	o["unit_ready"] = s.layer([[horn([392.0, 523.3], 0.12, 0.12, 0.35), 0.0, 1.0]])
	o["building_done"] = s.layer([[wood(180.0, 0.2), 0.0, 1.0], [wood(200.0, 0.2), 0.16, 0.9], [chime([659.3, 987.8], 0.08, 0.7), 0.3, 0.6]])
	o["age_up"] = horn([261.6, 329.6, 392.0, 523.3], 0.22, 0.24, 1.2)
	o["under_attack"] = horn([293.7, 293.7, 440.0], 0.18, 0.15, 0.6)
	o["victory"] = horn([392.0, 523.3, 659.3, 784.0, 659.3, 1046.5], 0.2, 0.22, 1.6)
	o["defeat"] = horn([392.0, 349.2, 311.1, 261.6], 0.35, 0.36, 1.6)
	o["player_defeated"] = s.reverb(s.layer([[s.env_perc(s.tone(110, 80, 1.2, "sine"), 0.01, 1.1), 0.0, 1.0], [chime([523.3, 466.2], 0.25, 1.0), 0.0, 0.4]]), 0.8, 0.3, 0.8)
	o["wonder_built"] = s.layer([[chime([523.3, 659.3, 784.0, 1046.5], 0.15, 1.6), 0.0, 1.0], [_choir(261.6, [1.0, 1.25, 1.5], 2.0), 0.0, 0.6]])
	o["market"] = _coins(5)
	o["tribute"] = _coins(8)


func _coins(count: int) -> PackedFloat32Array:
	var items := []
	for i in count:
		items.append([metal(s.rng.randf_range(2200, 3400), 0.12, 1.4), i * s.rng.randf_range(0.03, 0.07), s.rng.randf_range(0.4, 0.8)])
	return s.layer(items)


func _choir(root: float, ratios: Array, dur: float) -> PackedFloat32Array:
	var items := []
	for r in ratios:
		for det in [0.997, 1.003]:
			var f: float = root * r * det
			var src := s.tone(f, f, dur, "saw")
			s.tremolo(src, 5.0, 0.12)
			var v := s.formant(src, "a")
			s.env_adsr(v, dur * 0.3, 0.1, 0.8, dur * 0.4)
			items.append([v, 0.0, 0.35])
	return s.reverb(s.layer(items), 0.85, 0.35, 1.0)


# --- Selection / order "voices" ----------------------------------------------------------------------

func _voices(o: Dictionary) -> void:
	# Villagers: soft "hm?" and "ya" syllables.
	o["sel_villager_1"] = voice(150, "m", "e", 0.22, 1.0, 175)
	o["sel_villager_2"] = voice(180, "m", "a", 0.2, 1.1, 165)
	o["sel_villager_3"] = voice(210, "e", "a", 0.18, 1.2, 230)
	o["ack_villager_1"] = voice(160, "i", "a", 0.2, 1.0, 140)
	o["ack_villager_2"] = voice(190, "o", "u", 0.18, 1.1, 170)
	# Infantry: armour rattle plus a barked "hut!".
	for i in 2:
		var rattle := _chainmail(0.25)
		var bark := voice(120 + i * 25, "a", "u", 0.14, 0.9, 100)
		o["sel_infantry_%d" % (i + 1)] = s.layer([[rattle, 0.0, 0.5], [bark, 0.05, 1.0]])
		o["ack_infantry_%d" % (i + 1)] = s.layer([[_chainmail(0.3), 0.0, 0.6], [voice(135 + i * 20, "e", "a", 0.16, 0.95, 115), 0.0, 1.0]])
	o["sel_archer"] = s.layer([[s.env_perc(s.lowpass(s.tone(180, 240, 0.25, "saw"), 900), 0.02, 0.2), 0.0, 0.3], [voice(170, "e", "i", 0.15, 1.1, 190), 0.05, 0.9]])
	o["ack_archer"] = s.layer([[_chainmail(0.15), 0.0, 0.3], [voice(160, "a", "o", 0.16, 1.05, 140), 0.0, 1.0]])
	o["sel_gunner"] = s.layer([[_cock(), 0.0, 0.9], [voice(130, "a", "u", 0.14, 0.95, 110), 0.12, 0.8]])
	o["ack_gunner"] = s.layer([[_footsteps_march(3), 0.0, 0.6], [voice(125, "e", "u", 0.15, 0.95, 105), 0.0, 0.9]])
	o["sel_cavalry"] = _snort()
	o["ack_cavalry"] = s.layer([[_neigh(0.5), 0.0, 0.8], [_hooves(4, 0.09), 0.15, 0.7]])
	o["sel_camel"] = s.lowpass(_snort(), 900)
	o["ack_camel"] = s.layer([[voice(90, "o", "a", 0.45, 0.7, 70), 0.0, 0.9], [_hooves(3, 0.12), 0.2, 0.5]])
	o["sel_siege"] = _creak(0.4, 160)
	o["ack_siege"] = s.layer([[_creak(0.5, 120), 0.0, 0.7], [_rumble(0.6), 0.1, 0.7]])
	o["sel_ship"] = s.layer([[chime([880.0], 0.0, 0.8), 0.0, 0.5], [_creak(0.4, 110), 0.05, 0.6]])
	o["ack_ship"] = s.layer([[_splash(0.5), 0.0, 0.7], [_creak(0.35, 95), 0.1, 0.5]])
	o["sel_vehicle"] = _engine(0.6, 45, 55)
	o["ack_vehicle"] = s.layer([[_engine(0.8, 40, 80), 0.0, 1.0], [_tracks(0.8), 0.1, 0.4]])
	o["sel_aircraft"] = _prop(0.7)
	o["ack_aircraft"] = s.fade(whoosh(0.8, 300, 1800), 0.05, 0.2)
	o["sel_monk"] = _choir(196.0, [1.0, 1.5], 0.9)
	o["ack_monk"] = _choir(220.0, [1.0, 1.25, 1.5], 0.7)
	o["sel_trade"] = s.layer([[_creak(0.3, 140), 0.0, 0.6], [_coins(3), 0.05, 0.5]])
	o["ack_trade"] = s.layer([[_rumble(0.5), 0.0, 0.6], [_hooves(3, 0.15), 0.0, 0.4]])
	o["sel_balloon"] = s.layer([[burst(0.5, 300, 1200, 0.1, "pink"), 0.0, 0.8], [_creak(0.3, 200), 0.1, 0.4]])
	o["ack_balloon"] = burst(0.7, 200, 900, 0.15, "pink")


func _chainmail(dur: float) -> PackedFloat32Array:
	var items := []
	var count := int(dur * 40)
	for i in count:
		items.append([metal(s.rng.randf_range(3000, 5200), 0.04, 1.5), s.rng.randf() * dur, s.rng.randf_range(0.1, 0.35)])
	return s.layer(items)


func _cock() -> PackedFloat32Array:
	return s.layer([[metal(2600, 0.05, 1.2), 0.0, 0.7], [wood(500, 0.05), 0.0, 0.4], [metal(3300, 0.06, 1.2), 0.09, 0.8]])


func _footsteps_march(count: int) -> PackedFloat32Array:
	var items := []
	for i in count:
		items.append([burst(0.08, 80, 900, 0.002, "brown"), i * 0.16, 0.8])
	return s.layer(items)


func _snort() -> PackedFloat32Array:
	var b := burst(0.35, 300, 2500, 0.03)
	s.tremolo(b, 28.0, 0.6)
	return s.layer([[b, 0.0, 1.0], [burst(0.2, 200, 1500, 0.02), 0.32, 0.6]])


func _neigh(dur: float) -> PackedFloat32Array:
	var src := s.tone(520, 380, dur, "saw")
	s.tremolo(src, 16.0, 0.5)
	var v := s.formant_glide(src, "i", "a", 1.3)
	return s.env_adsr(v, 0.04, dur * 0.2, 0.6, dur * 0.5)


func _hooves(count: int, step: float) -> PackedFloat32Array:
	var items := []
	for i in count:
		items.append([wood(s.rng.randf_range(160, 220), 0.07), i * step + s.rng.randf() * 0.02, 0.8])
	return s.layer(items)


func _creak(dur: float, f: float) -> PackedFloat32Array:
	var src := s.tone(f, f * 1.35, dur, "saw")
	s.tremolo(src, 35.0, 0.7)
	s.bandpass(src, f * 3.0, 3.0)
	return s.env_adsr(src, 0.05, 0.1, 0.7, dur * 0.3)


func _rumble(dur: float) -> PackedFloat32Array:
	var b := s.lowpass(s.noise(dur, "brown"), 250)
	s.tremolo(b, 9.0, 0.4)
	return s.env_adsr(b, 0.05, 0.1, 0.8, dur * 0.3)


func _splash(dur: float) -> PackedFloat32Array:
	var b := s.noise(dur)
	s.lowpass_sweep(b, 5000, 600)
	s.highpass(b, 200)
	return s.env_perc(b, 0.01, dur)


func _engine(dur: float, f0: float, f1: float) -> PackedFloat32Array:
	var b := s.tone(f0, f1, dur, "square", 0.3)
	s.mix_into(b, s.tone(f0 * 2.02, f1 * 2.02, dur, "saw"), 0, 0.4)
	s.mix_into(b, s.lowpass(s.noise(dur, "brown"), 400), 0, 0.5)
	s.lowpass(b, 700)
	s.tremolo(b, 22.0, 0.3)
	return s.env_adsr(b, 0.08, 0.1, 0.8, dur * 0.25)


func _tracks(dur: float) -> PackedFloat32Array:
	var items := []
	var count := int(dur * 18)
	for i in count:
		items.append([metal(s.rng.randf_range(700, 1100), 0.04, 0.4), i / 18.0, 0.35])
	return s.layer(items)


func _prop(dur: float) -> PackedFloat32Array:
	var b := s.tone(70, 85, dur, "saw")
	s.lowpass(b, 600)
	s.tremolo(b, 38.0, 0.8)
	s.mix_into(b, s.gain(s.lowpass(s.noise(dur), 1500), 0.3), 0)
	return s.env_adsr(b, 0.1, 0.1, 0.8, dur * 0.3)


# --- Combat -----------------------------------------------------------------------------------------

func _combat(o: Dictionary) -> void:
	for i in 3:
		o["hit_sword_%d" % (i + 1)] = s.layer([[metal(s.rng.randf_range(1400, 2200), 0.35), 0.0, 1.0], [burst(0.06, 1500, 8000, 0.0005), 0.0, 0.6]])
		o["swing_%d" % (i + 1)] = whoosh(0.22 + i * 0.03, 700 + i * 200, 2400)
		o["hit_flesh_%d" % (i + 1)] = s.layer([[burst(0.12, 100, 1200, 0.001, "pink"), 0.0, 1.0], [s.env_perc(s.tone(140 + i * 20, 70, 0.12, "sine"), 0.001, 0.1), 0.0, 0.8]])
	for i in 2:
		o["hit_blunt_%d" % (i + 1)] = s.layer([[wood(110 + i * 30, 0.2), 0.0, 1.0], [burst(0.1, 80, 900, 0.001, "brown"), 0.0, 0.8]])
		o["bow_%d" % (i + 1)] = s.layer([[s.env_perc(s.pluck(98 + i * 12, 0.35, 0.8, 0.99), 0.001, 0.3), 0.0, 1.0], [whoosh(0.18, 1500, 4000), 0.03, 0.4]])
		o["arrow_hit_%d" % (i + 1)] = s.layer([[wood(260 + i * 60, 0.12), 0.0, 1.0], [burst(0.04, 1000, 6000, 0.0005), 0.0, 0.5]])
		o["musket_%d" % (i + 1)] = shot(0.4, 90 + i * 15, 4500)
		o["death_%d" % (i + 1)] = s.reverb(voice(140 - i * 15, "a", "u", 0.45, 0.9, 80), 0.5, 0.2, 0.3)
		o["explosion_%d" % (i + 1)] = s.reverb(explosion(1.3 + i * 0.3, 1.0 + i * 0.2), 0.8, 0.2, 0.6)
	o["death_3"] = s.reverb(voice(170, "o", "u", 0.35, 1.0, 95), 0.5, 0.2, 0.3)
	o["death_horse"] = s.layer([[_neigh(0.6), 0.0, 0.9], [wood(90, 0.3), 0.45, 0.8], [burst(0.3, 60, 600, 0.002, "brown"), 0.45, 0.7]])
	o["death_ship"] = s.layer([[_creak(0.8, 80), 0.0, 0.9], [_splash(1.2), 0.3, 1.0], [wood(70, 0.5), 0.1, 0.8]])
	o["death_vehicle"] = s.layer([[explosion(1.4, 1.1), 0.0, 1.0], [_chainmail(0.4), 0.1, 0.4]])
	o["death_animal"] = s.layer([[voice(260, "a", "u", 0.3, 1.4, 150), 0.0, 0.8], [burst(0.2, 60, 600, 0.002, "brown"), 0.2, 0.6]])
	o["crossbow"] = s.layer([[metal(1800, 0.12, 0.8), 0.0, 0.8], [wood(300, 0.1), 0.0, 0.8], [whoosh(0.15, 2000, 5000), 0.02, 0.4]])
	o["javelin"] = s.layer([[whoosh(0.3, 500, 1800), 0.0, 1.0], [voice(150, "a", "u", 0.1, 0.9, 120), 0.0, 0.4]])
	o["rifle"] = shot(0.45, 110, 6500)
	o["blunderbuss"] = s.layer([[shot(0.55, 70, 3500), 0.0, 1.0], [_chainmail(0.2), 0.02, 0.2]])
	var mg := []
	for i in 7:
		mg.append([shot(0.12, 130, 7000), i * 0.07, s.rng.randf_range(0.7, 1.0)])
	o["machine_gun"] = s.layer(mg)
	o["cannon"] = s.reverb(s.layer([[explosion(0.9, 0.8), 0.0, 1.0], [shot(0.5, 55, 2500), 0.0, 1.0]]), 0.85, 0.3, 0.9)
	o["artillery"] = s.reverb(s.layer([[explosion(1.0, 0.9), 0.0, 1.0], [shot(0.4, 60, 3500), 0.0, 1.0]]), 0.85, 0.3, 1.0)
	o["mortar"] = s.layer([[s.env_perc(s.tone(140, 90, 0.3, "sine"), 0.001, 0.25), 0.0, 1.0], [burst(0.3, 100, 2000, 0.001, "pink"), 0.0, 0.8]])
	o["catapult"] = s.layer([[wood(80, 0.35), 0.0, 1.0], [_creak(0.3, 120), 0.0, 0.5], [whoosh(0.5, 200, 900), 0.1, 0.6]])
	o["trebuchet"] = s.layer([[_creak(0.6, 70), 0.0, 0.7], [wood(60, 0.5), 0.4, 1.0], [whoosh(0.7, 150, 700), 0.45, 0.7]])
	o["scorpion"] = s.layer([[s.env_perc(s.pluck(70, 0.4, 0.9, 0.985), 0.001, 0.3), 0.0, 1.0], [wood(220, 0.15), 0.0, 0.8], [whoosh(0.2, 1200, 3500), 0.02, 0.4]])
	o["bazooka"] = s.layer([[shot(0.3, 80, 3000), 0.0, 0.7], [whoosh(0.7, 2500, 400), 0.02, 1.0]])
	o["tank_gun"] = s.reverb(s.layer([[explosion(0.7, 0.9), 0.0, 1.0], [shot(0.35, 50, 4000), 0.0, 1.0], [metal(500, 0.4, 0.6), 0.0, 0.3]]), 0.8, 0.3, 0.8)
	o["grenade_throw"] = s.layer([[whoosh(0.25, 600, 2000), 0.0, 1.0], [voice(140, "e", "u", 0.12, 0.95, 110), 0.0, 0.5]])
	o["bomb_whistle"] = s.fade(s.lowpass(s.tone(1400, 500, 0.9, "sine"), 3000), 0.1, 0.1)
	o["fire_ship"] = s.layer([[_fire(0.8), 0.0, 1.0], [whoosh(0.4, 300, 1200), 0.0, 0.5]])
	o["ram_hit"] = s.reverb(s.layer([[wood(55, 0.5), 0.0, 1.0], [burst(0.3, 50, 600, 0.001, "brown"), 0.0, 1.0]]), 0.6, 0.2, 0.4)
	o["building_hit_1"] = s.layer([[wood(130, 0.3), 0.0, 1.0], [burst(0.2, 200, 3000, 0.001, "pink"), 0.0, 0.7]])
	o["building_hit_2"] = s.layer([[wood(95, 0.35), 0.0, 1.0], [burst(0.25, 100, 2000, 0.001, "brown"), 0.0, 0.8]])
	o["collapse"] = s.reverb(s.layer([[explosion(2.2, 0.6), 0.0, 1.0], [_rubble(1.8), 0.15, 0.9], [wood(60, 0.8), 0.0, 0.7]]), 0.8, 0.25, 0.8)
	o["conversion"] = s.layer([[_choir(261.6, [1.0, 1.25, 1.5, 2.0], 1.6), 0.0, 1.0], [chime([1046.5, 1318.5, 1568.0], 0.12, 1.2), 0.4, 0.4]])
	o["heal"] = chime([1318.5, 1568.0, 2093.0], 0.07, 0.6)
	o["fire_loop"] = s.make_loop(_fire(6.0), 0.8)


func _rubble(dur: float) -> PackedFloat32Array:
	var items := []
	for i in int(dur * 25):
		items.append([wood(s.rng.randf_range(150, 600), s.rng.randf_range(0.05, 0.15)), s.rng.randf() * dur, s.rng.randf_range(0.2, 0.7)])
	return s.layer(items)


func _fire(dur: float) -> PackedFloat32Array:
	var roar := s.lowpass(s.noise(dur, "brown"), 500)
	s.tremolo(roar, 3.0, 0.3)
	var items := [[roar, 0.0, 0.7]]
	for i in int(dur * 22):
		items.append([s.env_perc(s.highpass(s.noise(0.02), 1500), 0.0005, 0.015), s.rng.randf() * dur, s.rng.randf_range(0.1, 0.6)])
	return s.layer(items)


# --- Economy --------------------------------------------------------------------------------------------

func _economy(o: Dictionary) -> void:
	for i in 3:
		o["chop_%d" % (i + 1)] = s.layer([[wood(s.rng.randf_range(180, 260), 0.18), 0.0, 1.0], [burst(0.05, 800, 5000, 0.0005), 0.0, 0.5]])
		o["mine_%d" % (i + 1)] = s.layer([[metal(s.rng.randf_range(2400, 3200), 0.18, 1.2), 0.0, 0.8], [burst(0.08, 400, 3000, 0.0005, "pink"), 0.0, 0.8], [_gravel(0.25), 0.03, 0.4]])
		o["build_%d" % (i + 1)] = s.layer([[wood(s.rng.randf_range(300, 420), 0.12), 0.0, 1.0], [metal(s.rng.randf_range(1500, 1900), 0.08, 0.6), 0.0, 0.3]])
	for i in 2:
		o["forage_%d" % (i + 1)] = s.fade(burst(0.35, 1500, 7000, 0.08, "pink"), 0.05, 0.15)
		o["farm_%d" % (i + 1)] = s.layer([[burst(0.3, 200, 2500, 0.05, "pink"), 0.0, 1.0], [wood(150 + i * 30, 0.08), 0.02, 0.5]])
		o["fish_%d" % (i + 1)] = _splash(0.5)
	o["drop_wood"] = s.layer([[wood(220, 0.12), 0.0, 1.0], [wood(180, 0.12), 0.07, 0.8], [wood(250, 0.12), 0.12, 0.7]])
	o["drop_food"] = s.layer([[burst(0.2, 80, 900, 0.002, "brown"), 0.0, 1.0], [wood(140, 0.1), 0.0, 0.5]])
	o["drop_gold"] = _coins(6)
	o["drop_stone"] = s.layer([[_gravel(0.35), 0.0, 1.0], [wood(110, 0.15), 0.0, 0.7]])
	o["tree_fall"] = s.layer([[_creak(0.7, 90), 0.0, 0.8], [burst(0.6, 1000, 6000, 0.2, "pink"), 0.4, 0.6], [wood(60, 0.5), 0.8, 1.0], [burst(0.4, 50, 500, 0.002, "brown"), 0.8, 0.9]])


func _gravel(dur: float) -> PackedFloat32Array:
	var items := []
	for i in int(dur * 60):
		items.append([s.env_perc(s.bandpass(s.noise(0.02), s.rng.randf_range(1500, 4500), 3.0), 0.0005, 0.015), s.rng.randf() * dur, s.rng.randf_range(0.2, 0.8)])
	return s.layer(items)


# --- Building selection sounds ---------------------------------------------------------------------------

func _buildings(o: Dictionary) -> void:
	o["bld_town_center"] = s.reverb(chime([523.3, 392.0], 0.35, 1.6), 0.8, 0.25, 0.6)
	o["bld_house"] = s.layer([[_creak(0.35, 180), 0.0, 0.7], [wood(200, 0.12), 0.3, 0.8]])
	o["bld_barracks"] = s.layer([[metal(1700, 0.6), 0.0, 0.9], [_chainmail(0.3), 0.05, 0.4]])
	o["bld_archery_range"] = s.layer([[s.env_perc(s.pluck(110, 0.4, 0.8, 0.99), 0.001, 0.35), 0.0, 1.0], [arrow_thunk(), 0.25, 0.8]])
	o["bld_stable"] = s.layer([[_neigh(0.5), 0.0, 0.8], [_hooves(3, 0.1), 0.4, 0.5]])
	o["bld_mill"] = s.layer([[_creak(0.7, 85), 0.0, 0.8], [wood(120, 0.2), 0.5, 0.5]])
	o["bld_lumber_camp"] = s.layer([[wood(220, 0.15), 0.0, 1.0], [wood(200, 0.15), 0.25, 0.8]])
	o["bld_mining_camp"] = s.layer([[metal(2800, 0.2, 1.2), 0.0, 0.8], [_gravel(0.3), 0.05, 0.6]])
	o["bld_blacksmith"] = s.layer([[metal(1200, 0.8, 1.2), 0.0, 1.0], [metal(1250, 0.6, 1.2), 0.28, 0.7]])
	o["bld_market"] = _coins(7)
	o["bld_dock"] = s.layer([[_splash(0.7), 0.0, 0.6], [_gull(), 0.15, 0.6]])
	o["bld_monastery"] = _choir(174.6, [1.0, 1.5, 2.0], 1.4)
	o["bld_castle"] = horn([196.0, 293.7], 0.25, 0.25, 0.8)
	o["bld_tower"] = s.reverb(chime([784.0], 0.0, 1.0), 0.6, 0.2, 0.4)
	o["bld_wall"] = s.layer([[wood(70, 0.3), 0.0, 1.0], [_gravel(0.25), 0.0, 0.6]])
	o["bld_farm"] = s.layer([[s.fade(burst(0.6, 1200, 6000, 0.15, "pink"), 0.1, 0.3), 0.0, 0.8], [_bird(2800.0, 3), 0.2, 0.4]])
	o["bld_university"] = s.layer([[_page_turn(), 0.0, 0.8], [chime([659.3, 880.0], 0.12, 0.8), 0.15, 0.5]])
	o["bld_siege_workshop"] = s.layer([[_creak(0.4, 130), 0.0, 0.8], [wood(140, 0.2), 0.2, 0.9], [wood(160, 0.2), 0.38, 0.7]])
	o["bld_storehouse"] = s.layer([[wood(160, 0.2), 0.0, 0.9], [_gravel(0.2), 0.05, 0.3]])
	o["bld_factory"] = s.layer([[_engine(0.9, 50, 50), 0.0, 0.7], [metal(900, 0.3, 0.8), 0.1, 0.6], [metal(950, 0.3, 0.8), 0.45, 0.5]])
	o["bld_airfield"] = _prop(1.0)
	o["bld_wonder"] = s.layer([[_choir(130.8, [1.0, 1.5, 2.0, 2.5], 2.0), 0.0, 1.0], [chime([523.3, 784.0], 0.3, 1.5), 0.2, 0.5]])
	o["bld_outpost"] = s.layer([[wood(190, 0.15), 0.0, 0.8], [_fire(0.6), 0.05, 0.4]])
	o["bld_gate"] = s.layer([[_creak(0.6, 70), 0.0, 0.9], [wood(60, 0.3), 0.5, 0.9]])


func arrow_thunk() -> PackedFloat32Array:
	return s.layer([[wood(280, 0.12), 0.0, 1.0], [burst(0.04, 1000, 6000, 0.0005), 0.0, 0.5]])


func _page_turn() -> PackedFloat32Array:
	return s.fade(burst(0.3, 2000, 8000, 0.05, "pink"), 0.05, 0.2)


func _gull() -> PackedFloat32Array:
	var items := []
	for i in 3:
		var src := s.tone(1400, 1100, 0.18, "saw")
		var v := s.formant_glide(src, "i", "a", 2.0)
		s.env_adsr(v, 0.02, 0.05, 0.6, 0.08)
		items.append([v, i * 0.17, 0.8 - i * 0.15])
	return s.layer(items)


# --- Animals ---------------------------------------------------------------------------------------------

func _animals(o: Dictionary) -> void:
	for i in 2:
		var src := s.tone(330 + i * 40, 300 + i * 30, 0.6, "saw")
		s.tremolo(src, 9.0 + i, 0.5)
		var v := s.formant_glide(src, "e", "a", 1.25)
		o["sheep_%d" % (i + 1)] = s.env_adsr(v, 0.04, 0.15, 0.7, 0.2)
		o["boar_%d" % (i + 1)] = s.layer([[_grunt(0.25, 90 + i * 15), 0.0, 1.0], [_grunt(0.2, 100 + i * 10), 0.3, 0.8]])
	var gob := []
	for i in 7:
		var g := s.tone(420, 380, 0.07, "saw")
		gob.append([s.env_perc(s.formant(g, "o", 1.4), 0.004, 0.06), i * 0.065, 0.9])
	o["turkey"] = s.layer(gob)
	o["deer"] = s.layer([[burst(0.25, 400, 3000, 0.02), 0.0, 0.7], [voice(420, "e", "a", 0.2, 1.6, 300), 0.1, 0.5]])
	var growl := s.tone(85, 70, 0.8, "saw")
	s.tremolo(growl, 24.0, 0.6)
	o["wolf_growl"] = s.env_adsr(s.formant(growl, "o", 0.9), 0.08, 0.2, 0.8, 0.3)
	o["wolf_howl"] = s.reverb(s.env_adsr(s.formant_glide(s.tone(420, 610, 1.8, "saw"), "u", "o", 1.0), 0.3, 0.3, 0.7, 0.8), 0.85, 0.35, 1.2)
	var roar := s.tone(140, 85, 1.1, "saw")
	s.mix_into(roar, s.gain(s.noise(1.1, "pink"), 0.5), 0)
	s.tremolo(roar, 30.0, 0.35)
	o["tiger_roar"] = s.drive(s.env_adsr(s.formant_glide(roar, "a", "o", 0.8), 0.05, 0.3, 0.7, 0.4), 1.8)
	var bear := s.tone(95, 60, 1.2, "saw")
	s.mix_into(bear, s.gain(s.noise(1.2, "brown"), 0.6), 0)
	s.tremolo(bear, 18.0, 0.4)
	o["bear_roar"] = s.drive(s.env_adsr(s.formant_glide(bear, "o", "u", 0.7), 0.08, 0.3, 0.7, 0.5), 1.6)
	o["herd_claim"] = s.layer([[_bell_small(), 0.0, 0.8], [_bell_small(), 0.18, 0.5]])


func _grunt(dur: float, f: float) -> PackedFloat32Array:
	var src := s.tone(f, f * 0.8, dur, "saw")
	s.mix_into(src, s.gain(s.noise(dur, "brown"), 0.8), 0)
	s.tremolo(src, 35.0, 0.6)
	return s.env_adsr(s.formant(src, "o", 0.8), 0.02, 0.05, 0.7, dur * 0.4)


func _bell_small() -> PackedFloat32Array:
	return s.partials(1900, [1.0, 2.6, 4.1], [1.0, 0.5, 0.2], [0.25, 0.15, 0.08], 0.3)


# --- Ambience ---------------------------------------------------------------------------------------------

func _bird(f: float, notes: int) -> PackedFloat32Array:
	var items := []
	var t := 0.0
	for i in notes:
		var d := s.rng.randf_range(0.04, 0.11)
		var f0 := f * s.rng.randf_range(0.85, 1.2)
		var b := s.tone(f0, f0 * s.rng.randf_range(0.7, 1.4), d, "sine")
		s.env_adsr(b, 0.005, d * 0.3, 0.6, d * 0.4)
		items.append([b, t, s.rng.randf_range(0.5, 1.0)])
		t += d + s.rng.randf_range(0.01, 0.08)
	return s.layer(items)


func _ambience(o: Dictionary) -> void:
	for i in 6:
		o["bird_%d" % (i + 1)] = _bird(s.rng.randf_range(2200, 4800), 3 + i)
	o["owl"] = s.reverb(s.layer([[_hoot(0.25), 0.0, 1.0], [_hoot(0.45), 0.35, 0.8]]), 0.8, 0.35, 0.8)
	o["rooster"] = s.layer([[voice(560, "e", "o", 0.15, 1.8, 700), 0.0, 0.7], [voice(700, "o", "o", 0.55, 1.8, 520), 0.15, 0.8]])
	o["gull"] = _gull()
	o["frog"] = _frogs()
	o["dawn_bell"] = s.reverb(chime([392.0, 392.0, 392.0], 1.1, 1.6), 0.85, 0.3, 1.5)
	var wind := s.noise(14.0, "pink")
	s.lowpass_sweep(wind, 500, 900)
	s.tremolo(wind, 0.13, 0.6)
	o["amb_wind"] = s.make_loop(wind, 2.0)
	var water := s.noise(12.0, "pink")
	s.lowpass(water, 900)
	s.tremolo(water, 0.17, 0.7)
	s.mix_into(water, s.gain(s.highpass(s.noise(12.0), 3000), 0.08), 0)
	o["amb_water"] = s.make_loop(water, 2.0)
	o["amb_night"] = s.make_loop(_crickets(12.0), 1.5)
	var leaves := s.noise(12.0)
	s.highpass(leaves, 1800)
	s.lowpass(leaves, 6000)
	s.tremolo(leaves, 0.23, 0.85)
	o["amb_forest"] = s.make_loop(leaves, 2.0)
	o["amb_battle"] = s.make_loop(_battle_bed(10.0), 1.5)
	o["engine_loop"] = s.make_loop(s.tremolo(_engine(4.0, 42, 42), 3.0, 0.15), 0.5)
	o["prop_loop"] = s.make_loop(_prop(4.0), 0.5)


func _hoot(dur: float) -> PackedFloat32Array:
	var b := s.tone(380, 340, dur, "sine")
	s.mix_into(b, s.gain(s.lowpass(s.noise(dur), 800), 0.1), 0)
	return s.env_adsr(b, 0.04, dur * 0.3, 0.6, dur * 0.4)


func _crickets(dur: float) -> PackedFloat32Array:
	var items := []
	for c in 5:
		var f := s.rng.randf_range(4000, 5200)
		var t := s.rng.randf() * 0.5
		var rate := s.rng.randf_range(0.4, 0.9)
		while t < dur:
			var chirp := s.tone(f, f, 0.12, "sine")
			s.tremolo(chirp, 45.0, 1.0)
			s.env_adsr(chirp, 0.01, 0.03, 0.8, 0.03)
			items.append([chirp, t, s.rng.randf_range(0.15, 0.35)])
			t += rate + s.rng.randf_range(-0.1, 0.1)
	var bed := s.layer(items)
	if bed.size() < s.n(dur):
		bed.append_array(s.silence(dur - float(bed.size()) / s.rate))
	return bed.slice(0, s.n(dur))


func _frogs() -> PackedFloat32Array:
	var items := []
	for i in 3:
		var src := s.tone(180, 160, 0.16, "square", 0.2)
		s.tremolo(src, 30.0, 0.8)
		items.append([s.env_adsr(s.formant(src, "o", 0.8), 0.01, 0.04, 0.7, 0.05), i * 0.22, 0.8])
	return s.layer(items)


func _battle_bed(dur: float) -> PackedFloat32Array:
	var items := [[s.lowpass(s.noise(dur, "brown"), 300), 0.0, 0.5]]
	for i in int(dur * 4):
		items.append([metal(s.rng.randf_range(1200, 2400), 0.2), s.rng.randf() * dur, s.rng.randf_range(0.05, 0.2)])
	for i in int(dur * 0.8):
		items.append([s.lowpass(voice(s.rng.randf_range(110, 170), "a", "o", 0.4, 0.9, 90), 1500), s.rng.randf() * dur, s.rng.randf_range(0.05, 0.15)])
	var bed := s.layer(items)
	return bed.slice(0, s.n(dur))


## Sounds added after the first release. Kept last so the random sequence of
## every earlier recipe (and so its file) stays the same.
func _extras(o: Dictionary) -> void:
	# Boarding / landing from a transport: steps on a wooden gangplank, a hull creak, lapping water.
	o["board"] = s.layer([[wood(190, 0.08), 0.0, 0.9], [wood(165, 0.08), 0.13, 0.8], [wood(210, 0.08), 0.26, 0.7],
		[_creak(0.35, 110), 0.05, 0.35], [_splash(0.4), 0.1, 0.3]])
	# Rally point: a banner stake knocked into the ground and the cloth snapping open.
	o["rally"] = s.layer([[wood(130, 0.18), 0.0, 1.0], [burst(0.08, 600, 4000, 0.002, "pink"), 0.09, 0.6], [burst(0.1, 500, 3500, 0.002, "pink"), 0.17, 0.45]])
