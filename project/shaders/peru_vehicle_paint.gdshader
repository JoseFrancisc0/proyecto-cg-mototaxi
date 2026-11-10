shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_texture : source_color,filter_linear_mipmap,repeat_disable;
uniform vec3 paint_color : source_color=vec3(0.8,0.2,0.1);
uniform bool red_paint=false;
void fragment(){
	vec3 original=texture(albedo_texture,UV).rgb;
	float strongest=max(original.r,max(original.g,original.b));
	float weakest=min(original.r,min(original.g,original.b));
	float mask=smoothstep(.13,.3,strongest-weakest);
	mask*=red_paint ? smoothstep(.08,.25,original.r-original.g) : smoothstep(.03,.16,original.g-original.b)*smoothstep(.0,.13,original.r-original.b);
	float value=dot(original,vec3(.30,.59,.11));
	ALBEDO=mix(original,paint_color*clamp(value*1.5,.12,1.1),mask*.87);
	ROUGHNESS=.67;METALLIC=.12;
}
