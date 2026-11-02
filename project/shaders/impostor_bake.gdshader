shader_type spatial;
// Horneado de impostores (tools/bake_impostors.gd). Dibuja el modelo real de un árbol sin luz
// desde una cámara ortográfica y guarda, según pass_mode:
//   0 = color: textura * tinte * oscurecimiento interior de la copa. Se guarda tal cual: en
//       Compatibility el SubViewport no convierte y el juego lee las texturas igual.
//   1 = normal en espacio de la cámara de esa vista (rg) y "hojosidad" (b) para la luz.
// La luz (sol, cielo, niebla, sombra del relieve) se calcula en el juego con estos datos,
// igual que en vegetation_textured.gdshader.
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_map = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut = 0.45;
uniform float leafiness = 0.0;
uniform float model_height = 10.0;
uniform int pass_mode = 0;

varying vec3 obj_normal;
varying vec3 obj_tangent;
varying vec3 obj_binormal;
varying float height01;

void vertex() {
	height01 = clamp(VERTEX.y / max(model_height, 0.1), 0.0, 1.0);
	obj_normal = NORMAL;
	obj_tangent = TANGENT;
	obj_binormal = BINORMAL;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	if (tex.a < alpha_cut) {
		discard;
	}
	if (pass_mode == 0) {
		float inner = mix(1.0, mix(0.55, 1.0, height01), leafiness);
		ALBEDO = clamp(tex.rgb * tint.rgb * inner, 0.0, 1.0);
	} else {
		vec3 N = normalize(obj_normal);
		if (use_normal_map) {
			vec3 nm = texture(normal_tex, UV).xyz * 2.0 - 1.0;
			N = normalize(normalize(obj_tangent) * nm.x + normalize(obj_binormal) * nm.y + N * nm.z);
		}
		// El modelo está en el origen sin transformar: objeto = mundo.
		vec3 nv = normalize((VIEW_MATRIX * vec4(N, 0.0)).xyz);
		if (nv.z < 0.0) {
			nv = -nv; // caras dobles (hojas): la normal mira hacia la cámara
		}
		ALBEDO = vec3(nv.xy * 0.5 + 0.5, leafiness);
	}
}
