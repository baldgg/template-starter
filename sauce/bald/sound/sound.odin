package sound

/*

Helpers for playing sound via FMOD.

Built to be a standalone package with no external dependencies.

*/

import fcore "fmod/core"
import fstudio "fmod/studio"

// you could use this during the build step to generate an enum list of sounds, that way you
// don't need to manually match it with the event:/name thing. But it's kinda overkill tbh.
// just typey typey
//import fsbank "fmod/fsbank"

import "core:strings"
import "core:log"
import "base:runtime"
import "base:intrinsics"
import "core:fmt"

import user "user:bald-user"

state: struct {
	initialized: bool,
	sound_ticks: u64,
	system: ^fstudio.SYSTEM,
	core_system: ^fcore.SYSTEM,
	bank: ^fstudio.BANK,
	strings_bank: ^fstudio.BANK,
	master_ch_group : ^fcore.CHANNELGROUP,
	
	sound_emitters: [dynamic]Sound_Emitter,
}

Sound_Emitter :: struct {
	event: ^fstudio.EVENTINSTANCE,
	last_update_tick: u64,
	unique_id: string,
}

INVALID_POS :: Vec2{ 99999, 99999 }

init :: proc() {
	using fstudio
	using state
	
	//when DEBUG {
	fmod_error_check(fcore.Debug_Initialize(fcore.DEBUG_LEVEL_WARNING, fcore.DEBUG_MODE.DEBUG_MODE_TTY, nil, "fmod.file"))
	//}

	fmod_error_check(System_Create(&system, fcore.VERSION))
	
	fmod_error_check(System_Initialize(system, 512, INIT_NORMAL, INIT_NORMAL, nil))
	
	fmod_error_check(System_LoadBankFile(system, strings.clone_to_cstring(fmt.tprintf("%v/fmod/Master.bank",user.res_path),context.temp_allocator), LOAD_BANK_NORMAL, &bank))
	fmod_error_check(System_LoadBankFile(system, strings.clone_to_cstring(fmt.tprintf("%v/fmod/Master.strings.bank",user.res_path),context.temp_allocator), LOAD_BANK_NORMAL, &strings_bank))

	System_GetCoreSystem(system, &core_system);
	
	fmod_error_check(fcore.System_GetMasterChannelGroup(core_system, &master_ch_group));

	state.initialized = true
}

update :: proc(listener_pos: Vec2, master_volume: f32) {
	using fstudio
	assert(state.initialized, "sound system not initted yet")
	
	// set master volume
	vol := master_volume
	vol = clamp(vol, 0.0, 1.0)
	fmod_error_check(fcore.ChannelGroup_SetVolume(state.master_ch_group, vol));
	
	fmod_error_check(System_Update(state.system))
	
	// update listener pos
	attributes : fcore._3D_ATTRIBUTES;
	attributes.position = {listener_pos.x, 0, listener_pos.y};
	attributes.forward = {0, 0, 1};
	attributes.up = {0, 1, 0};
	fmod_error_check(System_SetListenerAttributes(state.system, 0, attributes, nil));
}

play :: proc(name: string, pos := INVALID_POS, cooldown_ms :f32= 40.0) -> ^fstudio.EVENTINSTANCE {
	using fstudio
	using state
	
	event_desc: ^EVENTDESCRIPTION
	fmod_error_check(System_GetEvent(system, fmt.ctprint(name), &event_desc))
	
	instance: ^EVENTINSTANCE
	fmod_error_check(EventDescription_CreateInstance(event_desc, &instance))
	
	// force cooldown
	fmod_error_check(EventInstance_SetProperty(instance, .EVENT_PROPERTY_COOLDOWN, cooldown_ms/1000.0))
	
	fmod_error_check(EventInstance_Start(instance))
	
	// 3D
	attributes : fcore._3D_ATTRIBUTES;
	attributes.position = {pos.x, 0, pos.y};
	attributes.forward = {0, 0, 1};
	attributes.up = {0, 1, 0};
	fmod_error_check(EventInstance_Set3DAttributes(instance, &attributes));

	// auto-release when sound finished
	fmod_error_check(EventInstance_Release(instance));
	
	return instance
}

// note, this is separate to make it work with a fixed timestep
update_sound_emitters :: proc() {
	// yeet stale guys
	#reverse for &emitter, i in state.sound_emitters {
		if emitter.last_update_tick != state.sound_ticks {
		
			ok := stop(emitter.event)
			if !ok {
				log.error("failed to stop emitter. This would be bad because it'd keep playing perhaps. Unless it already died somehow?")
			}
		
			delete_emitter(&emitter)
			ordered_remove(&state.sound_emitters, i)
			log.info("killed sound emitter")
		}
	}

	state.sound_ticks += 1
}
@(private="file")
delete_emitter :: proc(emitter: ^Sound_Emitter) {
	delete(emitter.unique_id)
	emitter^ = {}
}

/*

Call every frame to continuously play a sound, and have it auto-stop playing when it no longer gets called.

unique_id gets appended to the name. This identifies the sound. Leave blank if you're absolutely sure you'll
only have one playing at a time and don't need to care about unique identification (like main menu music)

Passing position will update its position each frame.

Example for playing a sound at an entity's position continuously:

```
enemy: ^Entity  
unique_id := fmt.tprint(enemy.handle.id)  
play_emitter("event:/ambient_enemy_groan", unique_id, pos=enemy.pos)
```
*/
play_continuously :: proc(name: string, unique_id: string, pos := INVALID_POS) {

	unique_id := fmt.tprintf("%v%v", name, unique_id)

	// try find an existing one to update
	#reverse for &emitter, i in state.sound_emitters {
		if emitter.unique_id == unique_id {
			// store the latest tick so we don't get auto-removed at the end of the frame
			emitter.last_update_tick = state.sound_ticks

			// update position
			if pos != INVALID_POS {
				// #TODO, figure out why this is failing and have it not spam the console

				// this could fail, for fmod reasons...
				succ := update_pos(emitter.event, pos)
				if !succ {
					delete_emitter(&emitter)
					ordered_remove(&state.sound_emitters, i)
				}
			}

			return
		}
	}

	// couldn't find one, so we just make a new one
	emitter : Sound_Emitter
	emitter.event = play(name, pos=pos)
	emitter.last_update_tick = state.sound_ticks
	emitter.unique_id = strings.clone(unique_id)
	append(&state.sound_emitters, emitter)
	log.info("new sound emitter")
	
}

stop :: proc(event: ^fstudio.EVENTINSTANCE) -> bool {
	using state, fstudio
	ok := EventInstance_Stop(event, .STOP_ALLOWFADEOUT)
	return ok == .OK
}

update_pos :: proc(event: ^fstudio.EVENTINSTANCE, pos: Vec2) -> bool {
	using state, fstudio

	attrib: fcore._3D_ATTRIBUTES
	ok := EventInstance_Get3DAttributes(event, &attrib)
	if ok != .OK {
		log.warn("FMOD error getting 3d attributes:", fcore.error_string(ok))
	  return false
	}
	
	attrib.position = {pos.x, 0, pos.y}
	
	ok = EventInstance_Set3DAttributes(event, &attrib)
	if ok != .OK {
		log.warn("FMOD error setting 3d attributes:", fcore.error_string(ok))
		return false
	}
	
	return true
}

//
// helper stuff
//

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

@(private="file")
fmod_error_check :: proc(result: fcore.RESULT) {
	if result != .OK {
		log.error(fcore.error_string(result))
	}
}