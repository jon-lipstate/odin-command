package cmd

import "core:sys/windows"
import "core:mem"
import "core:fmt"
import "core:strings"
import "core:c"
import "core:c/libc"
import "core:runtime"
//
// main :: proc() {
// 	data, err := cmd("odin version", true, 128)
// 	fmt.print(string(data[:]))
// }

when ODIN_OS == .Darwin {
	foreign import lc "system:System.framework"
} else when ODIN_OS == .Linux {
	foreign import lc "system:c"
}

when ODIN_OS == .Darwin || ODIN_OS == .Linux {
	@(default_calling_convention = "c")
	foreign lc {
		popen :: proc(command: cstring, mode: cstring) -> ^libc.FILE ---
		pclose :: proc(stream: ^libc.FILE) -> int ---
	}
}

cmd :: proc(
	cmd: string,
	get_response := true,
	read_size := 4096,
) -> (
	data: [dynamic]u8,
	ok: bool,
) {
	when ODIN_OS == .Windows {
		sec_attr := windows.SECURITY_ATTRIBUTES {
			nLength        = size_of(windows.SECURITY_ATTRIBUTES),
			bInheritHandle = true,
		}
		jstr := []string{"cmd.exe /c ", cmd, "\x00"}
		command := strings.join(jstr, "");defer delete(command)
	
	
		io: IO_Pipes
		if !setup_child_io_pipes(&io, &sec_attr) {
			return nil, false
		}
		if !create_child_process(command, &io) {
			return nil, false
		}
		if get_response {
			data = make_dynamic_array_len_cap([dynamic]u8, 1, read_size)
			read_from_pipe(&data, read_size, &io)
		}
		ok = true
	} else when ODIN_OS == .Darwin || ODIN_OS == .Linux {
		cmd_cstr := strings.clone_to_cstring(cmd)
		defer delete(cmd_cstr)
		file := popen(cmd_cstr, cstring("r"))

		ok = file != nil

		if ok && get_response {
			data = make_dynamic_array_len([dynamic]u8, read_size)
			cstr := libc.fgets(cast(^byte)&data[0], i32(read_size), file)
			ok = cstr != nil
		}
		pclose(file)
	}

	return
}
