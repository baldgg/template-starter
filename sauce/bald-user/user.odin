package core_user

/*

These are concepts the core bald layer relies on.

But they vary from game-to-game, so this package is for interfacing with the core.

---

TODO, I wanna yeet this because it's a bit yuckie. Some notes:

We could likely untangle this and make the data required in the renderer just be stuff like blank types.
But it'd subtract from the ease of calling the high level draw functions, so probs not the best idea...

it would go from:

draw.draw_sprite(..., .shadow_medium, z_layer=.shadow, flags=.flag2)

^ types are known and can be inferred

to:

draw.draw_sprite(..., int(Sprite_Name.shadow_medium), z_layer=int(ZLayer.shadow), flags=u8(Quad_Flags.flag2))

^ unknown, so we'd need to do more typing

...

orrrr, maybe the solution is to just move the draw_sprite into the bald_helpers ??
that way we have the fast path by default with known types

then the lower level stuff would be unknown types and the renderer can not care...

that would probably be a good fix. will try that in future.

I'll keep this like this for now, since I'm not sure if there's gonna be other types we need in future that have a more tricky workaround needed.

*/

import "bald:utils"

//
// DRAW

Quad_Flags :: enum u8 {
	// #shared with the shader.glsl definition
	background_pixels = (1<<0),
	flag2 = (1<<1),
	flag3 = (1<<2),
}

ZLayer :: enum i8 {
	// Can add as many layers as you want in here.
	// Quads get sorted and drawn lowest to highest.
	// When things are on the same layer, they follow normal call order.
	nil,
	background=-90,
	shadow=-2,
	playspace=0,
	vfx,
	ui=75,
	tooltip,
	pause_menu,
	top,
}

//	is now auto generated

// Sprite_Name :: enum {
// 	nil,
// 	bald_logo,
// 	fmod_logo,
// 	player_still,
// 	shadow_medium,
// 	bg_repeat_tex0,
// 	player_death,
// 	player_run,
// 	player_idle,
// 	// to add new sprites, just put the .png in the res/images folder
// 	// and add the name to the enum here
// 	//
// 	// we could auto-gen this based on all the .png's in the images folder
// 	// but I don't really see the point right now. It's not hard to type lol.
// }

sprite_data: [Sprite_Name]Sprite_Data = #partial {
	.player_idle = {frame_count=2},
	.player_run = {frame_count=3}
}

Sprite_Data :: struct {
	frame_count: int,
	offset: Vec2,
	pivot: utils.Pivot,
}

get_sprite_offset :: proc(img: Sprite_Name) -> (offset: Vec2, pivot: utils.Pivot) {
	data := sprite_data[img]
	offset = data.offset
	pivot = data.pivot
	return
}

// #cleanup todo, this is kinda yuckie living in the bald-user
get_frame_count :: proc(sprite: Sprite_Name) -> int {
	frame_count := sprite_data[sprite].frame_count
	if frame_count == 0 {
		frame_count = 1
	}
	return frame_count
}


//
// helpers

import "core:math/linalg"
Matrix4 :: linalg.Matrix4f32
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32