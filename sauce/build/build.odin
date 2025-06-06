/*

Build script.

Note: doesn't make sense to abstract this away for re-use.
There's too many project-specific settings here, so it's not worth the effort.

*/

#+feature dynamic-literals
package build

import path "core:path/filepath"
import "core:fmt"
import "core:os/os2"
import "core:os"
import "core:strings"
import "core:log"
import "core:reflect"
import "core:time"

// we are assuming we're right next to the bald collection
import logger "../bald/utils/logger"
import utils "../bald/utils"

GEN_SPRITE_NAMES :: #config(GEN_SPRITE_NAMES, true)
res_path := #config(RES_PATH, "res")

EXE_NAME :: "game"

Target :: enum {
	windows,
	mac,
}

main :: proc() {


	context.logger = logger.logger()
	context.assertion_failure_proc = logger.assertion_failure_proc

	//fmt.println(os2.args)

	start_time := time.now()

	// note, ODIN_OS is built in, but we're being explicit
	assert(ODIN_OS == .Windows || ODIN_OS == .Darwin, "unsupported OS target")

	target: Target
	#partial switch ODIN_OS {
		case .Windows: target = .windows
		case .Darwin: target = .mac
		case: {
			log.error("Unsupported os:", ODIN_OS)
			return
		}
	}
	fmt.println("Building for", target)

	// gen the generated.odin
	{
		file := "sauce/generated.odin"

		f, err := os.open(file, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
		if err != nil {
			fmt.eprintln("Error:", err)
		}
		defer os.close(f)
		
		using fmt
		fprintln(f, "//")
		fprintln(f, "// MACHINE GENERATED via build.odin")
		fprintln(f, "// do not edit by hand!")
		fprintln(f, "//")
		fprintln(f, "")
		fprintln(f, "package main")
		fprintln(f, "")
		fprintln(f, "Platform :: enum {")
		fprintln(f, "	windows,")
		fprintln(f, "	mac,")
		fprintln(f, "}")

		fprintln(f, tprintf("PLATFORM :: Platform.%v", target))
	}

	// gen the generated.odin
	{
		file := "sauce/bald-user/generated.odin"

		f, err := os.open(file, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
		if err != nil {
			fmt.eprintln("Error:", err)
		}
		defer os.close(f)
		
		using fmt
		fprintln(f, "//")
		fprintln(f, "// MACHINE GENERATED via build.odin")
		fprintln(f, "// do not edit by hand!")
		fprintln(f, "//")
		fprintln(f, "")
		fprintln(f, "package core_user")
		fprintln(f, "")
		fprintln(f, "res_path ::",tprintf("\"%v\"",res_path))
		if GEN_SPRITE_NAMES{
			gen_sprite_names(f)
		}
	}
	
	// generate the shader
	// docs: https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md
	utils.fire("sokol-shdc", "-i", "sauce/bald/draw/shader_core.glsl", "-o", "sauce/bald-user/generated_shader.odin", "-l", "hlsl5:metal_macos", "-f", "sokol_odin")

	wd := os.get_current_directory()

	//utils.make_directory_if_not_exist("build")
	
	out_dir : string
	switch target {
		case .windows: out_dir = "build/windows_debug"
		case .mac: out_dir = "build/mac_debug"
	}

	full_out_dir_path := fmt.tprintf("%v/%v", wd, out_dir)
	log.info(full_out_dir_path)
	utils.make_directory_if_not_exist(full_out_dir_path)

	// build command
	{
		c: [dynamic]string = {
			"odin",
			"build",
			"sauce",
			"-debug",
			"-collection:bald=sauce/bald",
			"-collection:user=sauce",
			fmt.tprintf("-out:%v/%v.exe", out_dir, EXE_NAME),
		}
		// not needed, it's easier to just generate code into generated.odin
		//append(&c, fmt.tprintf("-define:TARGET_STRING=%v", target))
		utils.fire(..c[:])
	}

	// copy stuff into folder
	{
		// NOTE, if it already exists, it won't copy (to save build time)
		files_to_copy: [dynamic]string

		switch target {
			case .windows:
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/windows/x64/fmodstudio.dll")
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/windows/x64/fmodstudioL.dll")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/windows/x64/fmod.dll")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/windows/x64/fmodL.dll")

			case .mac:
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/darwin/libfmodstudio.dylib")
			append(&files_to_copy, "sauce/bald/sound/fmod/studio/lib/darwin/libfmodstudioL.dylib")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/darwin/libfmod.dylib")
			append(&files_to_copy, "sauce/bald/sound/fmod/core/lib/darwin/libfmodL.dylib")
		}

		for src in files_to_copy {
			dir, file_name := path.split(src)
			assert(os.exists(dir), fmt.tprint("directory doesn't exist:", dir))
			dest := fmt.tprintf("%v/%v", out_dir, file_name)
			if !os.exists(dest) {
				os2.copy_file(dest, src)
			}
		}
	}

	fmt.println("DONE in", time.diff(start_time, time.now()))
}




// value extraction example:
/*
target: Target
found: bool
for arg in os2.args {
	if strings.starts_with(arg, "target:") {
		target_string := strings.trim_left(arg, "target:")
		value, ok := reflect.enum_from_name(Target, target_string)
		if ok {
			target = value
			found = true
			break
		} else {
			log.error("Unsupported target:", target_string)
		}
	}
}
*/