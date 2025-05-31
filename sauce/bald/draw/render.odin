package draw

import user "user:bald-user"

import "bald:utils"
import "bald:utils/color"
import shape "bald:utils/shape"

import sapp "bald:sokol/app"
import sg "bald:sokol/gfx"
import sglue "bald:sokol/glue"
import slog "bald:sokol/log"

import "core:prof/spall"
import "core:mem"
import "core:log"
import "core:os"
import "core:fmt"

import "core:math"
import "core:math/linalg"
Matrix4 :: linalg.Matrix4f32
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

import stbi "vendor:stb/image"
import tt "vendor:stb/truetype"
import stbrp "vendor:stb/rect_pack"

Render_State :: struct {
	pass_action: sg.Pass_Action,
	pip: sg.Pipeline,
	bind: sg.Bindings,
}
render_state: Render_State

MAX_QUADS :: 8192
MAX_VERTS :: MAX_QUADS * 4

actual_quad_data: [MAX_QUADS * size_of(Quad)]u8

DEFAULT_UV :: Vec4 {0, 0, 1, 1}

clear_col: Vec4

Quad :: [4]Vertex;
Vertex :: struct {
	pos: Vec3,
	col: Vec4,
	uv: Vec2,
	local_uv: Vec2,
	size: Vec2,
	tex_index: u8,
	z_layer: u8,
	quad_flags: user.Quad_Flags,
	_: [1]u8,
	col_override: Vec4,
	params: Vec4,
}

render_init :: proc() {
	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
		d3d11_shader_debugging = ODIN_DEBUG,
	})

	load_sprites_into_atlas()
	load_font()

	// make the vertex buffer
	render_state.bind.vertex_buffers[0] = sg.make_buffer({
		usage = .DYNAMIC,
		size = size_of(actual_quad_data),
	})
	
	// make & fill the index buffer
	index_buffer_count :: MAX_QUADS*6
	indices,_ := mem.make([]u16, index_buffer_count, allocator=context.allocator)
	i := 0;
	for i < index_buffer_count {
		// vertex offset pattern to draw a quad
		// { 0, 1, 2,  0, 2, 3 }
		indices[i + 0] = auto_cast ((i/6)*4 + 0)
		indices[i + 1] = auto_cast ((i/6)*4 + 1)
		indices[i + 2] = auto_cast ((i/6)*4 + 2)
		indices[i + 3] = auto_cast ((i/6)*4 + 0)
		indices[i + 4] = auto_cast ((i/6)*4 + 2)
		indices[i + 5] = auto_cast ((i/6)*4 + 3)
		i += 6;
	}
	render_state.bind.index_buffer = sg.make_buffer({
		type = .INDEXBUFFER,
		data = { ptr = raw_data(indices), size = size_of(u16) * index_buffer_count },
	})
	
	// image stuff
	render_state.bind.samplers[user.SMP_default_sampler] = sg.make_sampler({})
	
	// setup pipeline
	// :vertex layout
	pipeline_desc : sg.Pipeline_Desc = {
		shader = sg.make_shader(user.quad_shader_desc(sg.query_backend())),
		index_type = .UINT16,
		layout = {
			attrs = {
				user.ATTR_quad_position = { format = .FLOAT3 },
				user.ATTR_quad_color0 = { format = .FLOAT4 },
				user.ATTR_quad_uv0 = { format = .FLOAT2 },
				user.ATTR_quad_local_uv0 = { format = .FLOAT2 },
				user.ATTR_quad_size0 = { format = .FLOAT2 },
				user.ATTR_quad_bytes0 = { format = .UBYTE4N },
				user.ATTR_quad_color_override0 = { format = .FLOAT4 },
				user.ATTR_quad_params0 = { format = .FLOAT4 },
			},
		},
		depth ={
			compare =.LESS_EQUAL,
			write_enabled=true,
		}
	}
	blend_state : sg.Blend_State = {
		enabled = true,
		src_factor_rgb = .SRC_ALPHA,
		dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
		op_rgb = .ADD,
		src_factor_alpha = .ONE,
		dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
		op_alpha = .ADD,
	}
	pipeline_desc.colors[0] = { blend = blend_state }
	render_state.pip = sg.make_pipeline(pipeline_desc)

	clear_col = utils.hex_to_rgba(0x090a14ff)
	
	// default pass action
	render_state.pass_action = {
		colors = {
			0 = { load_action = .CLEAR, clear_value = transmute(sg.Color)(clear_col)},
		},
	}
}

core_render_frame_start :: proc() {
	reset_draw_frame()
}

core_render_frame_end :: proc() {
	// merge all the layers into a big ol' array to draw
	total_quad_count := 0
	{
	
		total_quad_count += len(draw_frame.quads)

		assert(total_quad_count <= MAX_QUADS)
		offset := 0
	
		size := size_of(Quad) * len(draw_frame.quads)
		mem.copy(mem.ptr_offset(raw_data(actual_quad_data[:]), offset), raw_data(draw_frame.quads), size)
		offset += size
		
	}
	
	render_state.bind.images[user.IMG_tex0] = atlas.sg_image
	render_state.bind.images[user.IMG_font_tex] = font.sg_image

	{
		sg.update_buffer(
			render_state.bind.vertex_buffers[0],
			{ ptr = raw_data(actual_quad_data[:]), size = len(actual_quad_data) }
		)
		sg.begin_pass({ action = render_state.pass_action, swapchain = sglue.swapchain() })
		sg.apply_pipeline(render_state.pip)
		sg.apply_bindings(render_state.bind)
		sg.apply_uniforms(user.UB_Shader_Data, {ptr=&draw_frame.shader_data, size=size_of(user.Shader_Data)})
		sg.draw(0, 6*total_quad_count, 1)
		sg.end_pass()
	}

	sg.commit()
}

reset_draw_frame :: proc() {
	draw_frame.reset = {}
	clear(&draw_frame.quads)
}

Draw_Frame :: struct {
	quads: [dynamic]Quad,
	using reset: struct {
		// quads: [user.ZLayer][dynamic]Quad, // this is super scuffed, but I did this to optimise the sort, I'm sure there's a better fix.
		coord_space: Coord_Space,
		active_z_layer: user.ZLayer,
		active_scissor: shape.Rect,
		active_flags: user.Quad_Flags,
		using shader_data: user.Shader_Data,
	}

}
draw_frame: Draw_Frame

Sprite :: struct {
	width, height: i32,
	tex_index: u8,
	sg_img: sg.Image,
	data: [^]byte,
	atlas_uvs: Vec4,
}
sprites: [user.Sprite_Name]Sprite

load_sprites_into_atlas :: proc() {
	img_dir := fmt.tprintf("%v/images/",user.res_path)
	
	for img_name in user.Sprite_Name {
		if img_name == .nil do continue
		
		path := fmt.tprint(img_dir, img_name, ".png", sep="")
		png_data, succ := os.read_entire_file(path)
		assert(succ, fmt.tprint(path, "not found"))
		
		stbi.set_flip_vertically_on_load(1)
		width, height, channels: i32
		img_data := stbi.load_from_memory(raw_data(png_data), auto_cast len(png_data), &width, &height, &channels, 4)
		assert(img_data != nil, "stbi load failed, invalid image?")
			
		img : Sprite;
		img.width = width
		img.height = height
		img.data = img_data
		
		sprites[img_name] = img
	}
	
	// pack sprites into atlas
	{
		using stbrp

		// the larger we make this, the longer startup time takes
		LENGTH :: 1024
		atlas.w = LENGTH
		atlas.h = LENGTH
		
		cont : stbrp.Context
		nodes : [LENGTH]stbrp.Node
		stbrp.init_target(&cont, auto_cast atlas.w, auto_cast atlas.h, &nodes[0], auto_cast atlas.w)
		
		rects : [dynamic]stbrp.Rect
		rects.allocator = context.temp_allocator
		for img, id in sprites {
			if img.width == 0 {
				continue
			}
			append(&rects, stbrp.Rect{ id=auto_cast id, w=Coord(img.width+2), h=Coord(img.height+2) })
		}
		
		succ := stbrp.pack_rects(&cont, &rects[0], auto_cast len(rects))
		if succ == 0 {
			assert(false, "failed to pack all the rects, ran out of space?")
		}
		
		// allocate big atlas
		raw_data, err := mem.alloc(atlas.w * atlas.h * 4, allocator=context.temp_allocator)
		assert(err == .None)
		//mem.set(raw_data, 255, atlas.w*atlas.h*4)
		
		// copy rect row-by-row into destination atlas
		for rect in rects {
			img := &sprites[user.Sprite_Name(rect.id)]
			
			rect_w := int(rect.w) - 2
			rect_h := int(rect.h) - 2
			
			// copy row by row into atlas
			for row in 0..<rect_h {
				src_row := mem.ptr_offset(&img.data[0], int(row) * rect_w * 4)
				dest_row := mem.ptr_offset(cast(^u8)raw_data, ((int(rect.y+1) + row) * int(atlas.w) + int(rect.x+1)) * 4)
				mem.copy(dest_row, src_row, rect_w * 4)
			}
			
			// yeet old data
			stbi.image_free(img.data)
			img.data = nil;

			img.atlas_uvs.x = (cast(f32)rect.x+1) / (cast(f32)atlas.w)
			img.atlas_uvs.y = (cast(f32)rect.y+1) / (cast(f32)atlas.h)
			img.atlas_uvs.z = img.atlas_uvs.x + cast(f32)img.width / (cast(f32)atlas.w)
			img.atlas_uvs.w = img.atlas_uvs.y + cast(f32)img.height / (cast(f32)atlas.h)
		}
		
		when ODIN_OS == .Windows {
		stbi.write_png("atlas.png", auto_cast atlas.w, auto_cast atlas.h, 4, raw_data, 4 * auto_cast atlas.w)
		}
		
		// setup image for GPU
		desc : sg.Image_Desc
		desc.width = auto_cast atlas.w
		desc.height = auto_cast atlas.h
		desc.pixel_format = .RGBA8
		desc.data.subimage[0][0] = {ptr=raw_data, size=auto_cast (atlas.w*atlas.h*4)}
		atlas.sg_image = sg.make_image(desc)
		if atlas.sg_image.id == sg.INVALID_ID {
			log.error("failed to make image")
		}
	}
}
// We're hardcoded to use just 1 atlas now since I don't think we'll need more
// It would be easy enough to extend though. Just add in more texture slots in the shader
Atlas :: struct {
	w, h: int,
	sg_image: sg.Image,
}
atlas: Atlas


font_bitmap_w :: 256
font_bitmap_h :: 256
char_count :: 96
Font :: struct {
	char_data: [char_count]tt.bakedchar,
	sg_image: sg.Image,
}
font: Font
// note, this is hardcoded to just be a single font for now. I haven't had the need for multiple fonts yet.
// that'll probs change when we do localisation stuff. But that's farrrrr away. No need to complicate things now.
load_font :: proc() {
	using tt
	
	bitmap, _ := mem.alloc(font_bitmap_w * font_bitmap_h)
	font_height := 15 // for some reason this only bakes properly at 15 ? it's a 16px font dou...
	path := fmt.tprintf("%v/fonts/alagard.ttf",user.res_path) // #user
	ttf_data, err := os.read_entire_file(path)
	assert(ttf_data != nil, "failed to read font")
	
	ret := BakeFontBitmap(raw_data(ttf_data), 0, auto_cast font_height, auto_cast bitmap, font_bitmap_w, font_bitmap_h, 32, char_count, &font.char_data[0])
	assert(ret > 0, "not enough space in bitmap")
	
	when ODIN_OS == .Windows {
		//stbi.write_png("font.png", auto_cast font_bitmap_w, auto_cast font_bitmap_h, 1, bitmap, auto_cast font_bitmap_w)
	}
	
	// setup sg image so we can use it in the shader
	desc : sg.Image_Desc
	desc.width = auto_cast font_bitmap_w
	desc.height = auto_cast font_bitmap_h
	desc.pixel_format = .R8
	desc.data.subimage[0][0] = {ptr=bitmap, size=auto_cast (font_bitmap_w*font_bitmap_h)}
	sg_img := sg.make_image(desc)
	if sg_img.id == sg.INVALID_ID {
		log.error("failed to make image")
	}

	font.sg_image = sg_img
}




Coord_Space :: struct {
	proj: Matrix4,
	camera: Matrix4,
}

set_coord_space :: proc(coord: Coord_Space) {
	draw_frame.coord_space = coord
}

@(deferred_out=set_coord_space)
push_coord_space :: proc(coord: Coord_Space) -> Coord_Space {
	og := draw_frame.coord_space
	draw_frame.coord_space = coord
	return og
}



set_z_layer :: proc(zlayer: user.ZLayer) {
	draw_frame.active_z_layer = zlayer
}

@(deferred_out=set_z_layer)
push_z_layer :: proc(zlayer: user.ZLayer) -> user.ZLayer {
	og := draw_frame.active_z_layer
	draw_frame.active_z_layer = zlayer
	return og
}



draw_quad_projected :: proc(
	world_to_clip:   Matrix4, 

	// for each corner of the quad
	positions:       [4]Vec3,
	colors:          [4]Vec4,
	uvs:             [4]Vec2,

	tex_index: u8,

	// we've lost the original sprite by this point, but it can be useful to
	// preserve it for some stuff in the shader
	sprite_size: Vec2,

	// same as above
	col_override: Vec4,
	z_layer: user.ZLayer=.nil,
	flags: user.Quad_Flags,
	params:= Vec4{},
	z_layer_queue:=-1,
) {
	z_layer0 := z_layer
	if z_layer0 == .nil {
		z_layer0 = draw_frame.active_z_layer
	}

	verts : [4]Vertex
	defer {
		quad_array := &draw_frame.quads
		append(quad_array, verts)
	}
	
	verts[0].pos = (world_to_clip * Vec4{positions[0].x, positions[0].y, positions[0].z, 1.0}).xyz
	verts[1].pos = (world_to_clip * Vec4{positions[1].x, positions[1].y, positions[1].z, 1.0}).xyz
	verts[2].pos = (world_to_clip * Vec4{positions[2].x, positions[2].y, positions[2].z, 1.0}).xyz
	verts[3].pos = (world_to_clip * Vec4{positions[3].x, positions[3].y, positions[3].z, 1.0}).xyz
	
	verts[0].col = colors[0]
	verts[1].col = colors[1]
	verts[2].col = colors[2]
	verts[3].col = colors[3]

	verts[0].uv = uvs[0]
	verts[1].uv = uvs[1]
	verts[2].uv = uvs[2]
	verts[3].uv = uvs[3]
	
	verts[0].local_uv = {0, 0}
	verts[1].local_uv = {0, 1}
	verts[2].local_uv = {1, 1}
	verts[3].local_uv = {1, 0}

	verts[0].tex_index = tex_index
	verts[1].tex_index = tex_index
	verts[2].tex_index = tex_index
	verts[3].tex_index = tex_index
	
	verts[0].size = sprite_size
	verts[1].size = sprite_size
	verts[2].size = sprite_size
	verts[3].size = sprite_size
	
	verts[0].col_override = col_override
	verts[1].col_override = col_override
	verts[2].col_override = col_override
	verts[3].col_override = col_override
	
	verts[0].z_layer = u8(z_layer0)
	verts[1].z_layer = u8(z_layer0)
	verts[2].z_layer = u8(z_layer0)
	verts[3].z_layer = u8(z_layer0)
	
	flags0 := flags | draw_frame.active_flags	
	verts[0].quad_flags = flags0
	verts[1].quad_flags = flags0
	verts[2].quad_flags = flags0
	verts[3].quad_flags = flags0
	
	verts[0].params = params
	verts[1].params = params
	verts[2].params = params
	verts[3].params = params
}

atlas_uv_from_sprite :: proc(sprite: user.Sprite_Name) -> Vec4 {
	return sprites[sprite].atlas_uvs
}

get_sprite_size :: proc(sprite: user.Sprite_Name) -> Vec2 {
	return {f32(sprites[sprite].width), f32(sprites[sprite].height)}
}