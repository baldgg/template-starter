/*

This is just a big dump of random helpers.

It needs to be in a package, because it's helpful to share across projects or other packages.
Like the build.odin for example.

*/

package utils

import "core:os"
import "core:os/os2"
import "base:intrinsics"
import "base:runtime"
import "base:builtin"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:math/ease"
import "core:time"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:unicode"

// these are just shorthand defs
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Matrix4 :: linalg.Matrix4f32;
Vec2i :: [2]int

Pivot :: enum {
	bottom_left,
	bottom_center,
	bottom_right,
	center_left,
	center_center,
	center_right,
	top_left,
	top_center,
	top_right,
}

Direction :: enum {
	north,
	east,
	south,
	west,
}

scale_from_pivot :: proc(pivot: Pivot) -> Vec2 {
	switch pivot {
		case .bottom_left: return Vec2{0.0, 0.0}
		case .bottom_center: return Vec2{0.5, 0.0}
		case .bottom_right: return Vec2{1.0, 0.0}
		case .center_left: return Vec2{0.0, 0.5}
		case .center_center: return Vec2{0.5, 0.5}
		case .center_right: return Vec2{1.0, 0.5}
		case .top_center: return Vec2{0.5, 1.0}
		case .top_left: return Vec2{0.0, 1.0}
		case .top_right: return Vec2{1.0, 1.0}
	}
	return {};
}

vector_from_direction :: proc(dir: Direction) -> Vec2 {
	return Vec2{ f32(cardinal_direction_offset(int(dir)).x), f32(cardinal_direction_offset(int(dir)).y) }
}

// takes in 0..<4 (0,1,2,3) will panic otherwise
cardinal_direction_offset :: proc(i: int) -> Vec2i {
	switch i {
		case 0: return {0, 1} // north
		case 1: return {1, 0} // east
		case 2: return {0, -1} // south
		case 3: return {-1, 0} // west
		case:
		log.error("unknown direction", i)
		return {}
	}
}

rotation_from_direction :: proc(dir: Direction) -> f32 {
	switch dir {
		case .north: return 90
		case .east: return 0
		case .south: return 270
		case .west: return 180
	}
	return 0
}

fire :: proc(cmd: ..string) -> os2.Error {
	process, start_err := os2.process_start(os2.Process_Desc{
		command=cmd,
		stdout = os2.stdout,
		stderr = os2.stderr,
	})
	if start_err != nil {
		fmt.eprintln("Error:", start_err) 
		return start_err
	}

	_, wait_err := os2.process_wait(process)
	if wait_err != nil {
		fmt.eprintln("Error:", wait_err) 
		return wait_err
	}

	return nil
}

copy_dynamic_array :: proc(dest: ^$T/[dynamic]$E, src: T) {
	clear(dest)
	resize(dest, len(src))
	copy(dest[:], src[:])
}

crash_when_debug :: proc(args: ..any) {
	when ODIN_DEBUG {
		log.error(..args)
		runtime.trap()
	}
}

make_directory_if_not_exist :: proc(path: string) {
	if !os.exists(path) {
		err := os2.make_directory_all(path)
		if err != nil {
			log.error(err)
		}
	}
}

pct_chance :: proc(pct: f32) -> bool {
	return rand.float32() < pct
}

random_sign :: proc() -> f32 {
	return rand.int_max(2) == 0 ? 1.0 : -1.0
}

random_dir :: proc() -> Vec2 {
	return linalg.normalize(Vec2{ rand.float32_range(-1, 1), rand.float32_range(-1, 1) })
}

random_cardinal_dir_offset :: proc() -> Vec2i {
	return { rand_int(2)-1, rand_int(2)-1 }
}

append_if_not_exist :: proc(array: ^$T/[dynamic]$E, #no_broadcast arg: E) -> bool {
	for existing in array {
		if existing == arg {
			return false
		}
	}
	append(array, arg)
	return true
}

append_if_not_exist_hack :: proc(array: ^$T/[dynamic]$E, #no_broadcast arg: E) -> bool {
	// #hacky asf
	arg := arg
	for &existing in array {
		if runtime.memory_compare(&existing, &arg, size_of(E)) == 0 {
			return false
		}
	}
	append(array, arg)
	return true
}

snake_case_to_pretty_name :: proc(snake: string) -> string {
	using runtime
	name :Raw_String= transmute(Raw_String) fmt.aprint(snake, allocator=context.temp_allocator);
	for it in 0..<name.len
	{
		c := &name.data[it];
		if c^ == '_'
		{
			c^ = ' ';
			first_letter := &name.data[it+1];
			first_letter^ = u8(unicode.to_upper(rune(first_letter^)));
		}
	}
	if name.len > 0
	{
		name.data[0] = u8(unicode.to_upper(rune(name.data[0])));
	}
	return transmute(string)name;
}
xform_translate::proc{
	xform_translate_xy,
	xform_translate_xyz,
}

xform_translate_xy :: proc(pos: Vec2) -> Matrix4 {
	return linalg.matrix4_translate(Vec3{pos.x, pos.y, 0})
}
xform_translate_xyz :: proc(pos: Vec3) -> Matrix4 {
	return linalg.matrix4_translate(Vec3{pos.x, pos.y, pos.z})
}
xform_rotate :: proc(angle: f32) -> Matrix4 {
	return linalg.matrix4_rotate(math.to_radians(angle), Vec3{0,0,1})
}
xform_scale :: proc(scale: Vec2) -> Matrix4 {
	return linalg.matrix4_scale(Vec3{scale.x, scale.y, 1});
}

sine_breathe_alpha :: proc(p: $T) -> T where intrinsics.type_is_float(T) {
	return (math.sin((p - .25) * 2.0 * math.PI) / 2.0) + 0.5
}

animate_to_target_f32 :: proc(value: ^f32, target: f32, delta_t: f32, rate:f32= 15.0, good_enough:f32= 0.001) -> bool
{
	value^ += (target - value^) * (1.0 - math.pow_f32(2.0, -rate * delta_t));
	if almost_equals(value^, target, good_enough)
	{
		value^ = target;
		return true; // reached
	}
	return false;
}

animate_to_target_v2 :: proc(value: ^Vec2, target: Vec2, delta_t: f32, rate :f32= 15.0, good_enough:f32= 0.001)
{
	animate_to_target_f32(&value.x, target.x, delta_t, rate, good_enough)
	animate_to_target_f32(&value.y, target.y, delta_t, rate, good_enough)
}

almost_equals :: proc(a: f32, b: f32, epsilon: f32 = 0.001) -> bool
{
	return abs(a - b) <= epsilon;
}

float_alpha :: proc{
	float_alpha_f32, float_alpha_f64,
}
float_alpha_f32 :: proc(x: f32, min: f32, max: f32, clamp_result: bool = true) -> f32
{
	res := (x - min) / (max - min);
	if clamp_result { res = clamp(res, 0, 1); }
	return res;
}
float_alpha_f64 :: proc(x: f64, min: f64, max: f64, clamp_result: bool = true) -> f64
{
	res := (x - min) / (max - min);
	if clamp_result { res = clamp(res, 0, 1); }
	return res;
}

hex_to_rgba :: u32_to_rgba;
u32_to_rgba :: proc(v: u32) -> Vec4 {
	return Vec4{
		cast(f32)((v & 0xff000000)>>24)/255.0,
		cast(f32)((v & 0x00ff0000)>>16)/255.0,
		cast(f32)((v & 0x0000ff00)>>8) /255.0,
		cast(f32) (v & 0x000000ff)     /255.0,
	};
}

crash :: proc(args: ..any, loc:=#caller_location) {
	log.fatal(..args, location=loc)
}

ms_to_s :: proc(ms: f32) -> f32 {
	return ms / 1000.0
}

rotate_vector :: proc(vec: Vec2, angle: f32) -> Vec2 {
	c := math.cos(math.to_radians(angle))
	s := math.sin(math.to_radians(angle))

	return Vec2{
		vec.x * c - vec.y * s,
		vec.x * s + vec.y * c,
	}
}

angle_from_vector :: proc(v: Vec2) -> f32 {
	return math.to_degrees(math.atan2(v.y, v.x))
}

rand_f32_range :: rand.float32_range
rand_f64_range :: rand.float64_range
rand_int :: proc(max: int) -> int {
	return int(rand.int31_max(i32(max) + 1))
}

pretty_calendar_time :: proc(t: time.Time) -> string {
	_time_to_string_hms :: proc(t: time.Time, buf: []u8) -> (res: string) #no_bounds_check {
		assert(len(buf) >= time.MIN_HMS_LEN)
		h, m, s := time.clock(t)
	
		buf[7] = '0' + u8(s % 10); s /= 10
		buf[6] = '0' + u8(s)
		buf[5] = '-'
		buf[4] = '0' + u8(m % 10); m /= 10
		buf[3] = '0' + u8(m)
		buf[2] = '-'
		buf[1] = '0' + u8(h % 10); h /= 10
		buf[0] = '0' + u8(h)
	
		return string(buf[:time.MIN_HMS_LEN])
	}

	buf: [time.MIN_YYYY_DATE_LEN]u8
	ymd := time.to_string_yyyy_mm_dd(t, buf[:])
	
	buf2: [time.MIN_HMS_LEN]u8
	clock := _time_to_string_hms(t, buf2[:])
	
	return fmt.tprintf("%v_%v", ymd, clock)
}


// iso8601 format example
// 2023-12-13T15:45:30.123Z or YYYY-MM-DDTHH:MM:SSZ
//
time_to_iso :: proc(t: time.Time) -> string {
	buf: [time.MIN_YYYY_DATE_LEN]u8
	ymd := time.to_string_yyyy_mm_dd(t, buf[:])
	
	buf2: [time.MIN_HMS_LEN]u8
	clock := time.time_to_string_hms(t, buf2[:])
	
	return fmt.tprintf("%vT%vZ", ymd, clock)
}

// init_time will get set on first call
init_time: time.Time;
seconds_since_init :: proc() -> f64 {
	using time
	if init_time._nsec == 0 {
		init_time = time.now()
		return 0
	}
	return duration_seconds(since(init_time))
}