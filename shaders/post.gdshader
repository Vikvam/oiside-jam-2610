shader_type canvas_item;
// Full-screen post effect. mode: 0 blueprint, 1 phosphor CRT, 2 ink & paper.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;
uniform float danger = 0.0;      // 0..1, red/amber pulse at the edges
uniform float on_line = 0.0;     // 0..1, extra static when the line is open
uniform vec4 danger_color : source_color = vec4(1.0, 0.25, 0.2, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec2 barrel(vec2 uv, float k) {
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	return 0.5 + c * (1.0 + k * r2);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / vec2(textureSize(screen_tex, 0));
	vec3 col;
	float vig = 1.0;
	vec2 c = uv - 0.5;

	if (mode == 1) {
		vec2 buv = barrel(uv, 0.12);
		float inside = step(0.0, buv.x) * step(buv.x, 1.0) * step(0.0, buv.y) * step(buv.y, 1.0);
		// tiny horizontal jitter, stronger with static
		float jit = (hash(vec2(floor(buv.y * 240.0), floor(TIME * 30.0))) - 0.5) * px.x * (0.6 + 3.0 * on_line * step(0.97, hash(vec2(TIME, 1.0))));
		buv.x += jit;
		vec3 base = texture(screen_tex, buv).rgb;
		// cheap glow
		vec3 glow = vec3(0.0);
		for (int i = -2; i <= 2; i++) {
			glow += texture(screen_tex, buv + vec2(float(i) * 2.5, 0.0) * px).rgb;
			glow += texture(screen_tex, buv + vec2(0.0, float(i) * 2.5) * px).rgb;
		}
		glow /= 10.0;
		col = base + glow * 0.55;
		float scan = 0.75 + 0.25 * sin(buv.y * 720.0 * 3.14159);
		col *= scan;
		col *= 0.96 + 0.04 * sin(TIME * 50.0);
		col += (hash(buv * 900.0 + TIME) - 0.5) * (0.04 + 0.05 * on_line);
		vec2 cc = buv - 0.5;
		vig = smoothstep(0.85, 0.3, length(cc * vec2(1.0, 1.15))) * inside;
		c = cc;
	} else if (mode == 2) {
		// ink bleeding: slight offset smear
		vec3 base = texture(screen_tex, uv).rgb;
		vec3 smear = texture(screen_tex, uv + vec2(0.6, 0.4) * px).rgb;
		col = min(base, mix(base, smear, 0.5));
		// paper fibres
		float fib = vnoise(uv * vec2(900.0, 160.0)) * 0.5 + vnoise(uv * 300.0) * 0.5;
		col *= 0.93 + 0.07 * fib;
		float blot = smoothstep(0.62, 0.9, vnoise(uv * 6.0 + 3.1));
		col *= 1.0 - blot * 0.06;
		col += (hash(uv * 700.0 + floor(TIME * 8.0)) - 0.5) * 0.03;
		vig = smoothstep(1.0, 0.35, length(c * vec2(1.0, 1.2)));
		vig = mix(0.82, 1.0, vig);
	} else {
		vec3 base = texture(screen_tex, uv).rgb;
		col = base;
		float grain = hash(uv * 800.0 + floor(TIME * 12.0)) - 0.5;
		col += grain * (0.035 + 0.05 * on_line);
		// faint blueprint paper mottling
		col *= 0.95 + 0.05 * vnoise(uv * 40.0);
		vig = smoothstep(1.05, 0.3, length(c * vec2(1.0, 1.2)));
		vig = mix(0.7, 1.0, vig);
	}
	col *= vig;
	// danger pulse at edges
	float edge = smoothstep(0.25, 0.75, length(c * vec2(1.0, 1.25)));
	float pulse = 0.65 + 0.35 * sin(TIME * 6.0);
	col = mix(col, danger_color.rgb, edge * danger * pulse * 0.55);
	COLOR = vec4(col, 1.0);
}
