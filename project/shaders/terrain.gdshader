shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D sand_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_map : filter_linear, repeat_disable;
uniform sampler2D drainage_map : filter_linear, repeat_disable;
uniform float grid_cells = 256.0;
uniform float world_size = 256.0;
uniform float river_threshold = 20.0;
varying vec3 local_position;
varying vec3 local_normal;
void vertex() {
    local_position = VERTEX;
    local_normal = NORMAL;
}
void fragment() {
    vec2 map_uv = (UV * grid_cells + vec2(0.5)) / (grid_cells + 1.0);
    vec4 maps = texture(surface_map, map_uv);
    vec3 weights = max(maps.rgb, vec3(0.0));
    weights /= max(dot(weights, vec3(1.0)), 0.001);
    // Triplanar rock projection prevents stretching on steep slopes.
    vec3 blend = pow(abs(normalize(local_normal)), vec3(4.0));
    blend /= max(dot(blend, vec3(1.0)), 0.001);
    vec3 p = local_position / 10.0;
    vec3 rock = texture(rock_texture, p.yz).rgb * blend.x + texture(rock_texture, p.xz).rgb * blend.y + texture(rock_texture, p.xy).rgb * blend.z;
    vec3 sand = texture(sand_texture, p.xz).rgb;
    vec3 grass = texture(grass_texture, p.xz).rgb;
    vec3 ground = sand * weights.x + rock * weights.y + grass * weights.z;
    float cliff = smoothstep(0.15, 0.55, 1.0 - normalize(local_normal).y);
    ground = mix(ground, rock * 0.8, cliff);
    ground = mix(ground, rock * 1.15, smoothstep(65.0, 100.0, local_position.y));
    float stream = texture(drainage_map, map_uv).r;
    float river = smoothstep(river_threshold, river_threshold * 2.0, stream) * (1.0 - cliff);
    ground = mix(ground, vec3(0.035, 0.22, 0.28), river * (1.0 - maps.a));
    ground = mix(ground, vec3(0.31, 0.22, 0.13), maps.a * 0.85);
    ALBEDO = ground;
    ROUGHNESS = mix(0.95, 0.25, river * (1.0 - maps.a));
}
