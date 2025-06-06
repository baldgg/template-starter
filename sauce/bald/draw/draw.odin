package draw

/*

This package is a full-blown 2D pixel art renderer built on top of Sokol

This file contains all the top-level functions you might want to use to make a game.
see text.odin for the text helpers

Relies on the fact that we're generating a compatible shader via the build step with sokol-shdc.exe

*/


import "bald:utils"
import "bald:utils/color"
import user"user:bald-user"
import shape "bald:utils/shape"

import "core:mem"
import "core:log"
import "core:os"
import "core:fmt"
import "core:math"
import "core:math/linalg"

//
// high-level API
//

// draws an auto-sized sprite at a position
draw_sprite :: proc(
	pos: Vec2,

	// the rect drawn will auto-size based on this
	sprite: user.Sprite_Name,
	z:f32=0,
	// pivot of the sprite drawn
	pivot:=utils.Pivot.center_center,

	flip_x:=false,
	draw_offset:=Vec2{},

	// useful for more complex transforms. Could technically leave the pos blank on this + set
	// the pivot to bottom_left to fully control the transform of the sprite
	xform:=Matrix4(1),

	// used to offset the UV to the next frame
	anim_index:=0,

	// classic tint that gets multiplied with the sprite
	col:=color.WHITE,

	// overrides (mixes) the colour of the sprite
	// rgba = color to mix with + alpha component for strength
	// useful for doing a white flash
	col_override:Vec4={},

	// leave blank and it'll take the currently active layer
	z_layer:user.ZLayer={},

	// can do anything in the shader with these two things
	flags:user.Quad_Flags={},
	tex_index :u8=0,
	params:Vec4={},

	// crop
	crop_top:f32=0.0,
	crop_left:f32=0.0,
	crop_bottom:f32=0.0,
	crop_right:f32=0.0,
	pass:=current_pass,//sets what pass to draw to by defalt it is the one start pass set

) {

	rect_size := get_sprite_size(sprite)
	frame_count := user.get_frame_count(sprite)
	rect_size.x /= f32(frame_count)

	/* this was the old one
	
	// todo, incorporate this via sprite data
	offset, pivot := get_sprite_offset(img_id)
	
	xform0 := Matrix4(1)
	xform0 *= xform_translate(pos)
	xform0 *= xform // we slide in here because rotations + scales work nicely at this point
	xform0 *= xform_translate(offset + frame_size * -scale_from_pivot(pivot))
	*/

	xform0 := Matrix4(1)
	xform0 *= utils.xform_translate(pos)
	xform0 *= utils.xform_scale(Vec2{flip_x ? -1.0 : 1.0, 1.0})
	xform0 *= xform
	xform0 *= utils.xform_translate(rect_size * -utils.scale_from_pivot(pivot)) // pivot offset
	xform0 *= utils.xform_translate(-draw_offset) // extra draw offset for nudging into the desired pivot

	/*
	xform := xform
	if slight_overdraw {
		xform *= xform_translate(size / 2)
		xform *= xform_scale(Vec2(1.001))
		xform *= xform_translate(-size / 2)
	}
	*/

	draw_rect_xform(xform0, rect_size,z=z, sprite=sprite, anim_index=anim_index, col=col, col_override=col_override, z_layer=z_layer, flags=flags, params=params, crop_top=crop_top, crop_left=crop_left, crop_bottom=crop_bottom, crop_right=crop_right,pass=pass,tex_index=tex_index)
}

// draw a pre-positioned rect
draw_rect :: proc(
	rect: shape.Rect,
	z:f32=0,
	// these are explained below
	sprite:= user.Sprite_Name.nil,
	uv:= DEFAULT_UV,

	// draws an outline
	outline_col:=Vec4{},

	// I leave this out because I don't usually use it. I mainly use this function for UI drawing.
	// If needed, could add this in tho.
	//xform := Matrix4(1),

	// same as above
	col:=color.WHITE,
	col_override:Vec4={},
	z_layer:user.ZLayer={},
	flags:user.Quad_Flags={},
	params:Vec4={},
	crop_top:f32=0.0,
	crop_left:f32=0.0,
	crop_bottom:f32=0.0,
	crop_right:f32=0.0,
	tex_index:u8=0,
	pass:=current_pass,//sets what pass to draw to by defalt it is the one start pass set
) {
	// extract the transform from the rect
	xform := utils.xform_translate(rect.xy)
	size := shape.rect_size(rect)

	// draw outline if we have one
	if outline_col != {} {
		size := size
		xform := xform
		size += Vec2(2)
		xform *= utils.xform_translate(Vec2(-1))
		draw_rect_xform(xform, size, z, col=outline_col, uv=uv, col_override=col_override, z_layer=z_layer, flags=flags, params=params,pass=pass)
	}

	draw_rect_xform(xform, size, z, sprite, uv, tex_index, 0, col, col_override, z_layer, flags, params, crop_top, crop_left, crop_bottom, crop_right,pass=pass)
}

// #cleanup - this should be a utility
draw_sprite_in_rect :: proc(
	sprite: user.Sprite_Name, 
	pos: Vec2, 
	size: Vec2, 
	z:f32=0, 
	xform := Matrix4(1),
	col := color.WHITE,
	col_override:= Vec4{0,0,0,0},
	z_layer:=user.ZLayer.nil, 
	flags:=user.Quad_Flags(0), 
	pad_pct :f32= 0.1,
	pass:=current_pass,//sets what pass to draw to by defalt it is the one start pass set
){
	img_size := get_sprite_size(sprite)
	
	rect := shape.rect_make(pos, size)
	
	// make it smoller (padding)
	{
		rect = shape.rect_shift(rect, -rect.xy)
		rect.xy += size * pad_pct * 0.5
		rect.zw -= size * pad_pct * 0.5
		rect = shape.rect_shift(rect, pos)
	}
	
	// this shrinks the rect if the sprite is too smol
	{
		rect_size := shape.rect_size(rect)
		size_diff_x := rect_size.x - img_size.x
		if size_diff_x < 0 {
			size_diff_x = 0
		}
		
		size_diff_y := rect_size.y - img_size.y
		if size_diff_y < 0 {
			size_diff_y = 0
		}
		size_diff := Vec2{size_diff_x, size_diff_y}
		
		offset := rect.xy
		rect = shape.rect_shift(rect, -rect.xy)
		rect.xy += size_diff * 0.5
		rect.zw -= size_diff * 0.5
		rect = shape.rect_shift(rect, offset)
	}

	// TODO, there's a buggie wuggie in here somewhere...
	
	// ratio render lock
	if img_size.x > img_size.y { // long boi
		rect_size := shape.rect_size(rect)
		rect.w = rect.y + (rect_size.x * (img_size.y/img_size.x))
		// center along y
		new_height := rect.w - rect.y
		rect = shape.rect_shift(rect, Vec2{0, (rect_size.y - new_height) * 0.5})
	} else if img_size.y > img_size.x { // tall boi
		rect_size := shape.rect_size(rect)
		rect.z = rect.x + (rect_size.y * (img_size.x/img_size.y))
		// center along x
		new_width := rect.z - rect.x
		rect = shape.rect_shift(rect, Vec2{0, (rect_size.x - new_width) * 0.5})
	}
	
	draw_rect(rect,z=z, col=col, sprite=sprite, col_override=col_override, z_layer=z_layer, flags=flags,pass=pass)
}

draw_rect_xform :: proc(
	xform: Matrix4,
	size: Vec2,
	z:f32=0,
	
	// defaults to no sprite (blank color)
	sprite:= user.Sprite_Name.nil,

	// defaults to auto-grab the correct UV based on the sprite
	uv:= DEFAULT_UV,

	// by default this'll be the main texture atlas
	// can override though and use something else (like for the fonts)
	tex_index:u8=0,
	
	// same as above
	anim_index:=0,
	col:=color.WHITE,
	col_override:Vec4={},
	z_layer:user.ZLayer={},
	flags:user.Quad_Flags={},
	params:Vec4={},
	crop_top:f32=0.0,
	crop_left:f32=0.0,
	crop_bottom:f32=0.0,
	crop_right:f32=0.0,
	pass:=current_pass,//sets what pass to draw to by defalt it is the one start pass set
) {

	// apply ui alpha override
	col := col
	//col *= ui_state.alpha_mask

	uv := uv
	if uv == DEFAULT_UV && sprite!=nil{
		uv = atlas_uv_from_sprite(sprite)

		// animation UV hack
		// we assume all animations are just a long strip
		frame_count := user.get_frame_count(sprite)
		frame_size := size
		frame_size.x /= f32(frame_count)
		uv_size := shape.rect_size(uv)
		uv_frame_size := uv_size * Vec2{frame_size.x/size.x, 1.0}
		uv.zw = uv.xy + uv_frame_size
		uv = shape.rect_shift(uv, Vec2{f32(anim_index)*uv_frame_size.x, 0})
	}

	//
	// create a simple AABB rect
	// and transform it into clipspace, ready for the GPU
	// see: https://learnopengl.com/img/getting-started/coordinate_systems.png
	if pass.coord_space == {} {
		log.error("no coord space set!")
	}
	model := xform
	view := linalg.inverse(pass.coord_space.camera)
	projection := pass.coord_space.proj
	local_to_clip_space := projection * view * model

	// crop stuff
	size := size
	{
		if crop_top != 0.0 {
			utils.crash_when_debug("todo")
		}
		if crop_left != 0.0 {
			utils.crash_when_debug("todo")
		}
		if crop_bottom != 0.0 {
		
			crop := size.y * (1.0-crop_bottom)
			diff :f32= crop - size.y
			size.y = crop
			uv_size := shape.rect_size(uv)
			
			uv.y += uv_size.y * crop_bottom
			local_to_clip_space *= utils.xform_translate(Vec2{0, -diff})
		}
		if crop_right != 0.0 {
			size.x *= 1.0-crop_right
			
			uv_size := shape.rect_size(uv)
			uv.z -= uv_size.x * crop_right
		}
	}
	bl := Vec3{ 0, 0, z +cast(f32)z_layer}
	tl := Vec3{ 0, size.y, z +cast(f32)z_layer}
	tr := Vec3{ size.x, size.y, z +cast(f32)z_layer}
	br := Vec3{ size.x, 0, z +cast(f32)z_layer}

	tex_index := tex_index
	if tex_index == 0 && sprite == .nil {
		// make it not use a texture if we're blank
		tex_index = 255
	}

	draw_quad_projected(local_to_clip_space, {bl, tl, tr, br}, {col, col, col, col}, {uv.xy, uv.xw, uv.zw, uv.zy}, tex_index, size, col_override, z_layer, flags,params, pass=pass)
}