class_name Synth
extends RefCounted
## Offline procedural synthesis into AudioStreamWAV buffers.
## Everything is generated from code at startup: no audio assets.

const RATE := 22050


static func to_wav(buf: PackedFloat32Array, loop := false, gain := 1.0) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v := int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


static func blank(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * RATE))
	b.fill(0.0)
	return b


static func normalize(b: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in b.size():
		b[i] *= k
	return b


## One-pole lowpass in place.
static func lowpass(b: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in b.size():
		y += a * (b[i] - y)
		b[i] = y
	return b


static func highpass(b: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in b.size():
		y += a * (b[i] - y)
		b[i] = b[i] - y
	return b


## Two-pole resonator (band-pass) — returns a new buffer.
static func resonate(b: PackedFloat32Array, freq: float, q: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(b.size())
	var w := TAU * freq / RATE
	var r := 1.0 - w / (2.0 * q)
	r = clampf(r, 0.0, 0.9995)
	var c1 := 2.0 * r * cos(w)
	var c2 := -r * r
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var y := (1.0 - r) * b[i] + c1 * y1 + c2 * y2
		out[i] = y
		y2 = y1
		y1 = y
	return out


## Fade the last `sec` seconds to silence (avoids clicks at the end).
static func fade_out(b: PackedFloat32Array, sec := 0.01) -> PackedFloat32Array:
	var n := mini(int(sec * RATE), b.size())
	for i in n:
		b[b.size() - 1 - i] *= float(i) / n
	return b


static func add_into(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain := 1.0) -> void:
	for i in src.size():
		var j := (at + i) % dst.size()
		dst[j] += src[i] * gain


static func noise(sec: float) -> PackedFloat32Array:
	var b := blank(sec)
	for i in b.size():
		b[i] = randf() * 2.0 - 1.0
	return b


# ---------------------------------------------------------------- sounds

static func tick(freq := 2200.0, dur := 0.04) -> PackedFloat32Array:
	var b := blank(dur)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * freq * t) * 0.7 + (randf() * 2.0 - 1.0) * 0.5) * exp(-t * 160.0)
	return b


static func clock_loop() -> PackedFloat32Array:
	var b := blank(2.0)
	add_into(b, tick(2400.0), 0, 0.6)
	add_into(b, tick(1700.0), RATE, 0.5)
	return normalize(b, 0.5)


static func fan_loop() -> PackedFloat32Array:
	var sec := 2.0
	var n := noise(sec)
	n = lowpass(n, 700.0)
	var b := blank(sec)
	for i in b.size():
		var t := float(i) / RATE
		var hum := sin(TAU * 100.0 * t) * 0.35 + sin(TAU * 200.0 * t) * 0.15 + sin(TAU * 300.0 * t) * 0.07
		var blade := 0.75 + 0.25 * sin(TAU * 25.0 * t)
		b[i] = hum * 0.6 + n[i] * 2.2 * blade
	_crossfade_loop(b, 2000)
	return normalize(b, 0.5)


static func rain_loop() -> PackedFloat32Array:
	var sec := 3.0
	var b := lowpass(noise(sec), 2500.0)
	for i in b.size():
		b[i] *= 0.35
	for k in 140:
		var at := randi() % b.size()
		add_into(b, tick(randf_range(2500.0, 5500.0), 0.012), at, randf_range(0.1, 0.45))
	b = highpass(b, 300.0)
	_crossfade_loop(b, 3000)
	return normalize(b, 0.5)


static func clank(base := 180.0) -> PackedFloat32Array:
	var b := blank(0.9)
	var parts := [1.0, 2.76, 5.4, 8.93]
	for i in b.size():
		var t := float(i) / RATE
		var s := 0.0
		for k in parts.size():
			s += sin(TAU * base * parts[k] * t) * exp(-t * (6.0 + k * 5.0)) / (k + 1)
		b[i] = s + (randf() - 0.5) * exp(-t * 90.0)
	return b


static func radiator_loop() -> PackedFloat32Array:
	var sec := 5.0
	var b := lowpass(noise(sec), 120.0)
	for i in b.size():
		b[i] *= 3.0
	add_into(b, clank(170.0), int(RATE * 0.8), 0.5)
	add_into(b, clank(240.0), int(RATE * 3.1), 0.35)
	add_into(b, tick(900.0, 0.05), int(RATE * 3.3), 0.3)
	_crossfade_loop(b, 2000)
	return normalize(b, 0.5)


static func hiss_loop() -> PackedFloat32Array:
	var sec := 3.0
	var b := noise(sec)
	b = highpass(lowpass(b, 3500.0), 400.0)
	for i in b.size():
		b[i] *= 0.4
	for k in 18:
		add_into(b, tick(randf_range(1000.0, 4000.0), 0.006), randi() % b.size(), randf_range(0.2, 0.8))
	# 50 Hz mains hum, very faint
	for i in b.size():
		b[i] += sin(TAU * 50.0 * float(i) / RATE) * 0.05
	_crossfade_loop(b, 2000)
	return normalize(b, 0.4)


static func receiver_click() -> PackedFloat32Array:
	var b := blank(0.25)
	add_into(b, tick(1400.0, 0.03), 0, 1.0)
	add_into(b, tick(900.0, 0.04), int(RATE * 0.045), 0.6)
	var thump := blank(0.2)
	for i in thump.size():
		var t := float(i) / RATE
		thump[i] = sin(TAU * (120.0 - t * 200.0) * t) * exp(-t * 30.0)
	add_into(b, thump, int(RATE * 0.04), 0.5)
	return fade_out(normalize(b, 0.9), 0.02)


static func tap_knock() -> PackedFloat32Array:
	var b := blank(0.12)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * 520.0 * t) + sin(TAU * 1310.0 * t) * 0.5 + (randf() - 0.5)) * exp(-t * 70.0)
	return fade_out(normalize(b, 0.8), 0.02)


static func footstep(heavy := true) -> PackedFloat32Array:
	var b := blank(0.4)
	var f0 := 52.0 if heavy else 85.0
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		phase += (f0 + 45.0 * exp(-t * 35.0)) / RATE
		b[i] = sin(TAU * phase) * exp(-t * (14.0 if heavy else 22.0))
	# heel scuff: low-passed noise, short
	var n := lowpass(lowpass(noise(0.4), 350.0), 350.0)
	for i in b.size():
		var t := float(i) / RATE
		b[i] += n[i] * 4.0 * exp(-t * 45.0)
	# floorboard creak on some steps (quiet, mid-range)
	if randf() < 0.35:
		var cr := blank(0.3)
		var f := randf_range(320.0, 520.0)
		for i in cr.size():
			var t := float(i) / RATE
			cr[i] = sin(TAU * (f + 40.0 * sin(t * 25.0)) * t) * sin(PI * t / 0.3) * 0.06
		add_into(b, cr, int(RATE * 0.05), 1.0)
	return fade_out(normalize(b, 0.9), 0.03)


static func breath() -> PackedFloat32Array:
	var sec := 2.6
	var n := noise(sec)
	var a := resonate(n, 900.0, 2.0)
	var c := resonate(n, 1800.0, 3.0)
	var b := blank(sec)
	for i in b.size():
		var t := float(i) / RATE
		# in (0..1.0) — pause — out (1.3..2.5)
		var env := 0.0
		if t < 1.0:
			env = sin(PI * t / 1.0) * 0.6
		elif t > 1.25:
			env = sin(PI * (t - 1.25) / 1.3)
		b[i] = (a[i] + c[i] * 0.6) * env
	return normalize(b, 0.8)


static func bell(base := 440.0, sec := 3.0) -> PackedFloat32Array:
	var b := blank(sec)
	var parts := [[0.5, 1.0, 0.8], [1.0, 0.8, 1.0], [1.19, 0.5, 1.4], [1.56, 0.4, 2.0], [2.0, 0.3, 2.6], [2.74, 0.2, 3.5]]
	for i in b.size():
		var t := float(i) / RATE
		var s := 0.0
		for p in parts:
			s += sin(TAU * base * p[0] * t) * p[1] * exp(-t * p[2])
		b[i] = s * minf(1.0, t * 400.0)
	return normalize(b, 0.8)


static func crash() -> PackedFloat32Array:
	var sec := 1.4
	var b := lowpass(noise(sec), 3000.0)
	for i in b.size():
		var t := float(i) / RATE
		b[i] *= exp(-t * 4.0) * 1.5
		b[i] += sin(TAU * (55.0 + 30.0 * exp(-t * 10.0)) * t) * exp(-t * 6.0) * 1.2
	add_into(b, clank(310.0), int(RATE * 0.05), 0.8)
	add_into(b, clank(470.0), int(RATE * 0.2), 0.5)
	add_into(b, footstep(true), int(RATE * 0.4), 0.7)
	return fade_out(normalize(b, 0.95), 0.2)


## Low, slowly beating drone for mood. Seamless 8 s loop (all partials
## complete whole cycles in 8 s).
static func drone() -> PackedFloat32Array:
	var sec := 8.0
	var b := blank(sec)
	var parts := [[55.0, 0.5], [55.125, 0.45], [82.5, 0.25], [110.25, 0.12], [164.875, 0.06]]
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for p in parts:
			v += sin(TAU * p[0] * t) * p[1]
		# slow swell
		v *= 0.75 + 0.25 * sin(TAU * t / sec)
		b[i] = v
	return normalize(b, 0.5)


## European ringback: 425 Hz, one second on.
static func ringback() -> PackedFloat32Array:
	var b := blank(1.0)
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(1.0, minf(t * 80.0, (1.0 - t) * 80.0))
		b[i] = sin(TAU * 425.0 * t) * 0.6 * env
	return b


static func heartbeat() -> PackedFloat32Array:
	var b := blank(1.0)
	var beat := func(f: float) -> PackedFloat32Array:
		var x := blank(0.18)
		for i in x.size():
			var t := float(i) / RATE
			x[i] = sin(TAU * f * t) * exp(-t * 22.0)
		return x
	add_into(b, beat.call(55.0), 0, 1.0)
	add_into(b, beat.call(48.0), int(RATE * 0.28), 0.7)
	return normalize(b, 0.9)


## A syllable of "voice": glottal pulse train shaped by two formants.
static func syllable(f0: float, f1: float, f2: float, sec := 0.13) -> PackedFloat32Array:
	var src := blank(sec)
	var phase := 0.0
	for i in src.size():
		var t := float(i) / RATE
		var f := f0 * (1.0 + 0.06 * sin(t * 18.0)) * (1.0 - 0.15 * t / sec)
		phase += f / RATE
		if phase >= 1.0:
			phase -= 1.0
		# asymmetric glottal pulse + breathiness
		src[i] = (pow(1.0 - phase, 3.0) - 0.25) + (randf() - 0.5) * 0.35
	var a := resonate(src, f1, 6.0)
	var c := resonate(src, f2, 9.0)
	var b := blank(sec)
	for i in b.size():
		var t := float(i) / RATE
		var env := sin(PI * t / sec)
		b[i] = (a[i] + c[i] * 0.7) * env * env
	return normalize(highpass(b, 250.0), 0.8)


static func _crossfade_loop(b: PackedFloat32Array, n: int) -> void:
	## Blend the tail into the head so the loop seam is inaudible.
	var size := b.size()
	n = mini(n, size / 4)
	for i in n:
		var f := float(i) / n
		b[i] = b[i] * f + b[size - n + i] * (1.0 - f)
	b.resize(size - n)
