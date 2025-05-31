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


gen_sprite_names::proc(f:os.Handle){
    file_info:= dir_path_to_file_infos("res/images")
	fmt.fprintln(f, "")
    fmt.fprintln(f, "Sprite_Name :: enum {")
    fmt.fprintln(f, "	nil,")
    for fil in file_info {
        if strings.has_suffix(fil.name,"png"){
            fmt.fprintln(f,"	",strings.trim_suffix(fil.name,".png"),",",sep="")
        }
    }
    fmt.fprintln(f, "}")
}

dir_path_to_file_infos :: proc(path: string) -> []os.File_Info {
	d, derr := os.open(path, os.O_RDONLY)
	if derr != 0 {
		fmt.print(os.get_current_directory(),"\n")
		fmt.print("\n |path| ",path,"\n")
		panic("open failed")
	}
	defer os.close(d)

	{
		file_info, ferr := os.fstat(d)
		defer os.file_info_delete(file_info)

		if ferr != 0 {
			panic("stat failed")
		}
		if !file_info.is_dir {
			panic("not a directory")
		}
	}

	file_infos, _ := os.read_dir(d, -1)
	return file_infos
}