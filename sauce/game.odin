#+feature dynamic-literals
package main

/*

This is the file where you actually make the game.

It will grow pretty phat. This is where the magic happens.

GAMEPLAY O'CLOCK !

*/
import user "user:bald-user"

import "bald:input"
import "bald:draw"
import "bald:sound"
import "bald:utils"
import "bald:utils/color"


import "core:log"
import "core:fmt"
import "core:mem"
import "core:math"
import "core:math/linalg"

import sg "bald:sokol/gfx"
import sapp "bald:sokol/app"
import spall "core:prof/spall"

VERSION :string: "v0.0.0"
WINDOW_TITLE :: "Template [bald]"
GAME_RES_WIDTH :: 480
GAME_RES_HEIGHT :: 270
window_w := 1280
window_h := 720
cam:=&ctx.gs.cam

when NOT_RELEASE {
	// can edit stuff in here to be whatever for testing
	PROFILE :: false
} else {
	// then this makes sure we've got the right settings for release
	PROFILE :: false
}

//
// epic game state

Game_State :: struct {
	ticks: u64,
	game_time_elapsed: f64,
	cam_pos: Vec2, // this is used by the renderer
	cam:draw.Camera,
	// entity system
	entity_top_count: int,
	latest_entity_id: int,
	entities: [MAX_ENTITIES]Entity,
	entity_free_list: [dynamic]int,

	// sloppy state dump
	player_handle: Entity_Handle,

	scratch: struct {
		all_entities: []Entity_Handle,
	}
}

//
// action -> key mapping

action_map: map[Input_Action]input.Key_Code = {
	.left = .A,
	.right = .D,
	.up = .W,
	.down = .S,
	.click = .LEFT_MOUSE,
	.use = .RIGHT_MOUSE,
	.interact = .E,
}

Input_Action :: enum u8 {
	left,
	right,
	up,
	down,
	click,
	use,
	interact,
}
// passes

bace_pass: draw.Draw_Pass_Info
offs_pass: draw.Draw_Pass_Info

//
// entity system

Entity :: struct {
	handle: Entity_Handle,
	kind: Entity_Kind,

	// todo, move this into static entity data
	update_proc: proc(^Entity),
	draw_proc: proc(Entity),

	// big sloppy entity state dump.
	// add whatever you need in here.
	pos: Vec2,
	last_known_x_dir: f32,
	flip_x: bool,
	draw_offset: Vec2,
	draw_pivot: Pivot,
	rotation: f32,
	hit_flash: Vec4,
	sprite: Sprite_Name,
	anim_index: int,
  next_frame_end_time: f64,
  loop: bool,
  frame_duration: f32,
	
	// this gets zeroed every frame. Useful for passing data to other systems.
	scratch: struct {
		col_override: Vec4,
	}
}

Entity_Kind :: enum {
	nil,
	player,
	thing1,
}


entity_setup :: proc(e: ^Entity, kind: Entity_Kind) {
	// entity defaults
	e.draw_proc = draw_entity_default
	e.draw_pivot = .bottom_center

	switch kind {
		case .nil:
		case .player: setup_player(e)
		case .thing1: setup_thing1(e)
	}
}

//
// main game procs

app_shutdown :: proc() {
	// called on exit
	delete(bace_pass.quads)
}

app_init :: proc() {
	init_cam(&ctx.gs.cam)

	draw.init_pass_defalts(pass=&bace_pass) //inits defalt draw pass
	draw.init_pass_render_texture_wh(pass=&offs_pass,w=500,h=500) //inits a drapas using a render texture


	draw.bind_imag_to_pass(pass=&bace_pass,imag=draw.get_render_texture_from_pass(pass=&offs_pass),slot=user.IMG_test) //binds the render texture to the slot
	draw.bind_imag_to_pass(pass=&offs_pass,imag=draw.atlas.sg_image,slot=user.IMG_test) //binds a placeholder texture to the slot so there is know worning

	draw.clear_background(pass=&offs_pass,clear_color={.3,.3,.3,.6})
	draw.start_pass(pass=&offs_pass,cam=&ctx.gs.cam)
	{
		// ui space example
		draw.push_coord_space(get_pixl_space(500,500))

		draw.draw_text({0, 0}, "this is a render texture and is only drawn one time.", z_layer=.ui, pivot=Pivot.center_center)
		draw.draw_sprite({100, 100}, .player_still, col_override=Vec4{1,0,1,1}, z=-1)
		draw.draw_sprite({-100, 100}, .player_still, col_override=Vec4{0,0,1,.4}, z=-1,)
		draw.draw_sprite({-100, -100}, .player_still, col_override=Vec4{1,0,0,.4}, z=-11)
		draw.draw_sprite({100, -100}, .player_still, col_override=Vec4{0,0,1,.4}, z=11,)
	}
	draw.end_pass(pass=&offs_pass)

}

app_frame :: proc() {
	// right now we are just calling the game update, but in future this is where you'd do a big
	// "UX" switch for startup splash, main menu, settings, in-game, etc
	sound.play_continuously("event:/ambiance", "")
	game_update()

	game_draw()

	volume :f32= 0.75
	sound.update(get_player().pos, volume)
}

game_update :: proc() {

	draw.start_pass(pass=&bace_pass,cam=&ctx.gs.cam)//some things may need to know stuff about the bace pass

	ctx.gs.scratch = {} // auto-zero scratch for each update
	defer {
		// update at the end
		ctx.gs.game_time_elapsed += f64(ctx.delta_t)
		ctx.gs.ticks += 1
	}
	
	// this'll be using the last frame's camera position, but it's fine for most things
	draw.push_coord_space(get_world_space())

	
	// setup world for first game tick
	if ctx.gs.ticks == 0 {
		player := entity_create(.player)
		ctx.gs.player_handle = player.handle
	}

	
	rebuild_scratch_helpers()
	
	// big :update time
	for handle in get_all_ents() {
		e := entity_from_handle(handle)

		update_entity_animation(e)

		if e.update_proc != nil {
			e.update_proc(e)
		}
	}

	if input.key_pressed(.LEFT_MOUSE) {
		input.consume_key_pressed(.LEFT_MOUSE)

		pos := mouse_pos_in_current_space()
		log.info("schloop at", pos)
		sound.play("event:/schloop", pos=pos)
	}
	t_cam_pos:=ctx.gs.cam.pos.xy
	utils.animate_to_target_v2(&t_cam_pos, get_player().pos, ctx.delta_t, rate=10)
	ctx.gs.cam.pos.xy=t_cam_pos
	// ... add whatever other systems you need here to make epic game
}

game_draw :: proc() {
	draw.clear_background(pass=&bace_pass,clear_color = {.05,.1,.3,1})

	// this is a exsample of doing a sepret draw_pass
	{
		draw.start_pass(pass=&bace_pass,cam=&ctx.gs.cam)
		draw.push_coord_space(get_world_space())
		draw.current_pass.ndc_to_world_xform = get_world_space_camera() * linalg.inverse(get_world_space_proj())
		draw.draw_text({0, 250}, "hello world.",z=4, pivot=Pivot.bottom_center)
		draw.end_pass(pass=&bace_pass)
	}

	draw.start_pass(pass=&bace_pass,cam=&ctx.gs.cam)

	{
		// ui space example
		draw.push_coord_space(get_screen_space())
		x, y := screen_pivot(.top_left)
		x += 2
		y -= 2
		draw.draw_text({x,y}, "hello world.", z_layer=.ui, pivot=Pivot.top_left,)
	}

	// this is so we can get the current pixel in the shader in world space (VERYYY useful)
	draw.current_pass.ndc_to_world_xform = get_world_space_camera() * linalg.inverse(get_world_space_proj())
	draw.current_pass.bg_repeat_tex0_atlas_uv = draw.atlas_uv_from_sprite(.bg_repeat_tex0)

	// background thing
	{
		// identity matrices, so we're in clip space
		draw.push_coord_space({get_clip_space_proj(), get_clip_space_camera()})
		// draw rect that covers the whole screen
		draw.draw_rect(Rect{ -1, -1, 1, 1}, flags=.background_pixels,z_layer = .background) // we leave it in the hands of the shader
	}


	// world
	{
		draw.push_coord_space(get_world_space())

		// draws the render texture										tex_index is for what image to draw frome this was set in app_init()
		draw.draw_rect(Rect{ -100, -270, 100, -70},z_layer = .background,tex_index=2)

		draw.draw_sprite({10, 10}, .player_still, col_override=Vec4{0,0,1,.4}, z=-1,)
		draw.draw_sprite({-10, 10}, .player_still, col_override=Vec4{1,0,1,.4}, z=1,)
		draw.draw_text({0, -50}, "sugon", pivot=.bottom_center, col={0,0,0,0.1})

		for handle in get_all_ents() {
			e := entity_from_handle(handle)
			e.draw_proc(e^)
		}
	}
	draw.end_pass(pass=&bace_pass)
}

rebuild_scratch_helpers :: proc() {
	// construct the list of all entities on the temp allocator
	// that way it's easier to loop over later on
	all_ents := make([dynamic]Entity_Handle, 0, len(ctx.gs.entities), allocator=context.temp_allocator)
	for &e in ctx.gs.entities {
		if !is_valid(e) do continue
		append(&all_ents, e.handle)
	}
	ctx.gs.scratch.all_entities = all_ents[:]
}

// note, this needs to be in the game layer because it varies from game to game.
// Specifically, stuff like anim_index and whatnot aren't guarenteed to be named the same or actually even be on the base entity.
// (in terrafactor, it's inside a sub state struct)
draw_entity_default :: proc(e: Entity) {
	e := e // need this bc we can't take a reference from a procedure parameter directly

	if e.sprite == nil {
		return
	}

	xform := utils.xform_rotate(e.rotation)

	draw_sprite_entity(&e, e.pos, e.sprite, xform=xform, anim_index=e.anim_index, draw_offset=e.draw_offset, flip_x=e.flip_x, pivot=e.draw_pivot)
}

// helper for drawing a sprite that's based on an entity.
// useful for systems-based draw overrides, like having the concept of a hit_flash across all entities
draw_sprite_entity :: proc(
	entity: ^Entity,

	pos: Vec2,
	sprite: Sprite_Name,
	z:f32=0,
	pivot:=utils.Pivot.center_center,
	flip_x:=false,
	draw_offset:=Vec2{},
	xform:=Matrix4(1),
	anim_index:=0,
	col:=color.WHITE,
	col_override:Vec4={},
	z_layer:ZLayer={},
	flags:Quad_Flags={},
	params:Vec4={},
	crop_top:f32=0.0,
	crop_left:f32=0.0,
	crop_bottom:f32=0.0,
	crop_right:f32=0.0,
) {

	col_override := col_override

	col_override = entity.scratch.col_override
	if entity.hit_flash.a != 0 {
		col_override.xyz = entity.hit_flash.xyz
		col_override.a = max(col_override.a, entity.hit_flash.a)
	}

	draw.draw_sprite(
		pos=pos, 
		sprite=sprite, 
		z=z, pivot=pivot, 
		flip_x=flip_x, 
		draw_offset=draw_offset, 
		xform=xform, 
		anim_index=anim_index, 
		col=col, 
		col_override=col_override, 
		z_layer=z_layer, 
		flags=flags, 
		params=params, 
		crop_top=crop_top, 
		crop_left=crop_left, 
		crop_bottom=crop_bottom, 
		crop_right=crop_right,
	)
}

//
// ~ Gameplay Slop Waterline ~
//
// From here on out, it's gameplay slop time.
// Structure beyond this point just slows things down.
//
// No point trying to make things 'reusable' for future projects.
// It's trivially easy to just copy and paste when needed.
//

// shorthand for getting the player
get_player :: proc() -> ^Entity {
	return entity_from_handle(ctx.gs.player_handle)
}

setup_player :: proc(e: ^Entity) {
	e.kind = .player

	// this offset is to take it from the bottom center of the aseprite document
	// and center it at the feet
	e.draw_offset = Vec2{0.5, 5}
	e.draw_pivot = .bottom_center

	e.update_proc = proc(e: ^Entity) {

		input_dir := get_input_vector()
		e.pos += input_dir * 100.0 * ctx.delta_t

		if input_dir.x != 0 {
			e.last_known_x_dir = input_dir.x
		}

		e.flip_x = e.last_known_x_dir < 0

		if input_dir == {} {
			entity_set_animation(e, .player_idle, 0.3)
		} else {
			entity_set_animation(e, .player_run, 0.1)
		}

		e.scratch.col_override = Vec4{0,0,1,0.2}
	}

	e.draw_proc = proc(e: Entity) {
		draw.draw_sprite(e.pos, .shadow_medium, col={1,1,1,0.2})
		draw_entity_default(e)
	}
}

setup_thing1 :: proc(using e: ^Entity) {
	kind = .thing1
}

entity_set_animation :: proc(e: ^Entity, sprite: Sprite_Name, frame_duration: f32, looping:=true) {
	if e.sprite != sprite {
		e.sprite = sprite
		e.loop = looping
		e.frame_duration = frame_duration
		e.anim_index = 0
		e.next_frame_end_time = 0
	}
}
update_entity_animation :: proc(e: ^Entity) {
	if e.frame_duration == 0 do return

	frame_count := get_frame_count(e.sprite)

	is_playing := true
	if !e.loop {
		is_playing = e.anim_index + 1 <= frame_count
	}

	if is_playing {
	
		if e.next_frame_end_time == 0 {
			e.next_frame_end_time = now() + f64(e.frame_duration)
		}
	
		if end_time_up(e.next_frame_end_time) {
			e.anim_index += 1
			e.next_frame_end_time = 0
			//e.did_frame_advance = true
			if e.anim_index >= frame_count {

				if e.loop {
					e.anim_index = 0
				}

			}
		}
	}
}