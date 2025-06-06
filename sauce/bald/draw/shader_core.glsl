
// syntax reference: https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md
@header package core_user
@header import sg "bald:sokol/gfx"

@ctype vec4 Vec4
@ctype mat4 Matrix4

//
// VERTEX SHADER
//
@vs vs
in vec3 position;
in vec4 color0;
in vec2 uv0;
in vec2 local_uv0;
in vec2 size0;
in vec4 bytes0;
in vec4 color_override0;
in vec4 params0;

out vec4 color;
out vec2 uv;
out vec2 local_uv;
out vec2 size;
out vec4 bytes;
out vec4 color_override;
out vec4 params;

out vec2 pos;

void main() {
	gl_Position = vec4(position, 1);
	color = color0;
	uv = uv0;
	local_uv = local_uv0;
	bytes = bytes0;
	color_override = color_override0;
	size = size0;
	params = params0;
	
	pos = gl_Position.xy;
}
@end


//
// FRAGMENT SHADER
//
@fs fs

layout(binding=0) uniform texture2D tex0;
layout(binding=1) uniform texture2D font_tex;
layout(binding=2) uniform texture2D test;


layout(binding=0) uniform sampler default_sampler;

in vec4 color;
in vec2 uv;
in vec2 local_uv;
in vec2 size;
in vec4 bytes;
in vec4 color_override;
in vec4 params;

in vec2 pos;

out vec4 col_out;

@include shader_utils.glsl

@include ../../shader.glsl // this is the user's fragment shader

@end

@program quad vs fs