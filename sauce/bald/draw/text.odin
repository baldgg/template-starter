package draw

import user "user:bald-user"
import "bald:utils"
import "bald:utils/color"
import shape "bald:utils/shape"

import tt "vendor:stb/truetype"

draw_text :: draw_text_with_drop_shadow

draw_text_wrapped :: proc(
	pos: Vec2,
	text: string,
	z:f32=0, 
	wrap_width: f32, 
	col:=color.WHITE, 
	scale:= 1.0, 
	pivot:=utils.Pivot.bottom_left, 
	z_layer:= user.ZLayer.nil, 
	col_override:=Vec4{0,0,0,0},
	pass:=current_pass,//sets what pass to draw to by defalt it is the one start pass set
) -> Vec2 {
	
	// TODO
	return draw_text_no_drop_shadow(pos, text,z, col, scale, pivot, z_layer, col_override,pass=pass)
}

draw_text_with_drop_shadow :: proc(
	pos: Vec2,
	text: string,
	z:f32=0,
	drop_shadow_col:=color.BLACK,
	col:=color.WHITE,
	scale:= 1.0,
	pivot:=utils.Pivot.bottom_left,
	z_layer:= user.ZLayer.nil,
	col_override:=Vec4{0,0,0,0},
	pass:=current_pass,//sets what pass to draw to by defalt it is the one start pass set
) -> Vec2 {
	
	offset := Vec2{1,-1} * f32(scale)
	draw_text_no_drop_shadow(pos+offset, text,z=z, col=drop_shadow_col*col,scale=scale,pivot=pivot,z_layer=z_layer,col_override=col_override)
	dim := draw_text_no_drop_shadow(pos, text,z=z, col=col,scale=scale,pivot=pivot,z_layer=z_layer,col_override=col_override)
	
	return dim
}

draw_text_no_drop_shadow :: proc(
	pos: Vec2,
	text: string,
	z:f32=0,
	col:=color.WHITE, 
	scale:= 1.0, 
	pivot:=utils.Pivot.bottom_left, 
	z_layer:= user.ZLayer.nil, 
	col_override:=Vec4{0,0,0,0},
	pass:=current_pass,//sets what pass to draw to by defalt it is the one start pass set
) -> (text_bounds: Vec2) {

	using tt

	push_z_layer(z_layer != .nil ? z_layer : draw_frame.active_z_layer)

	// loop thru and find the text size box thingo
	total_size : Vec2
	for char, i in text {
		
		advance_x: f32
		advance_y: f32
		q: aligned_quad
		GetBakedQuad(&font.char_data[0], font_bitmap_w, font_bitmap_h, cast(i32)char - 32, &advance_x, &advance_y, &q, false)
		// this is the the data for the aligned_quad we're given, with y+ going down
		// x0, y0,     s0, t0, // top-left
		// x1, y1,     s1, t1, // bottom-right
		
		size := Vec2{ abs(q.x0 - q.x1), abs(q.y0 - q.y1) }
		
		bottom_left := Vec2{ q.x0, -q.y1 }
		top_right := Vec2{ q.x1, -q.y0 }
		assert(bottom_left + size == top_right)
		
		if i == len(text)-1 {
			total_size.x += size.x
		} else {
			total_size.x += advance_x
		}
		
		total_size.y = max(total_size.y, top_right.y)
	}
	
	pivot_offset := total_size * -utils.scale_from_pivot(pivot)
	
	debug_text := false
	if debug_text {
		draw_rect(shape.rect_make(pos + pivot_offset, total_size), col=color.BLACK,pass=pass)
	}
	
	// draw glyphs one by one
	x: f32
	y: f32
	for char in text {
		
		advance_x: f32
		advance_y: f32
		q: aligned_quad
		GetBakedQuad(&font.char_data[0], font_bitmap_w, font_bitmap_h, cast(i32)char - 32, &advance_x, &advance_y, &q, false)
		// this is the the data for the aligned_quad we're given, with y+ going down
		// x0, y0,     s0, t0, // top-left
		// x1, y1,     s1, t1, // bottom-right
		
		size := Vec2{ abs(q.x0 - q.x1), abs(q.y0 - q.y1) }
		
		bottom_left := Vec2{ q.x0, -q.y1 }
		top_right := Vec2{ q.x1, -q.y0 }
		assert(bottom_left + size == top_right)
		
		offset_to_render_at := Vec2{x,y} + bottom_left
		
		offset_to_render_at += pivot_offset
		
		uv := Vec4{
			q.s0, q.t1,
			q.s1, q.t0
		}
							
		xform := Matrix4(1)
		xform *= utils.xform_translate(pos)
		xform *= utils.xform_scale(Vec2{auto_cast scale, auto_cast scale})
		xform *= utils.xform_translate(offset_to_render_at)
		
		if debug_text {
			draw_rect_xform(xform, size, col=Vec4{1,1,1,0.8})
		}
		
		draw_rect_xform(xform, size, uv=uv, tex_index=1, col_override=col_override, col=col,z=z,z_layer=z_layer,pass=pass)
		
		x += advance_x
		y += -advance_y
	}

	return total_size * f32(scale)
}