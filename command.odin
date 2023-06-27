package cmd

import "core:sys/windows"
import "core:mem"
import "core:fmt"
import "core:strings"
import "core:c"
import "core:runtime"
//
// main :: proc() {
// 	data, err := cmd("odin version", true, 128)
// 	fmt.print(string(data[:]))
// }

// Adapted from: https://codereview.stackexchange.com/questions/188630/send-command-and-get-response-from-windows-cmd-prompt-silently-follow-up
HANDLE :: windows.HANDLE
IO_Pipes :: struct {
	read_in:   HANDLE,
	write_in:  HANDLE,
	read_out:  HANDLE,
	write_out: HANDLE,
}
cmd :: proc(
	cmd: string,
	get_response := true,
	read_size := 4096,
) -> (
	data: [dynamic]u8,
	ok: bool,
) {
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

	return
}
//
setup_child_io_pipes :: proc(io: ^IO_Pipes, sa_attr: ^windows.SECURITY_ATTRIBUTES) -> (ok: bool) {
	if !windows.CreatePipe(&io.read_out, &io.write_out, sa_attr, 0) {
		return
	}
	if !windows.SetHandleInformation(io.read_out, windows.HANDLE_FLAG_INHERIT, 0) {
		return
	}
	if !windows.CreatePipe(&io.read_in, &io.write_in, sa_attr, 0) {
		return
	}
	if !windows.SetHandleInformation(io.write_in, windows.HANDLE_FLAG_INHERIT, 0) {
		return
	}
	return true
}
//
create_child_process :: proc(cmd: string, io: ^IO_Pipes) -> (ok: bool) {
	pi: windows.PROCESS_INFORMATION = {}
	si: windows.STARTUPINFOW = {
		cb         = size_of(windows.STARTUPINFOW),
		hStdError  = io.write_out,
		hStdOutput = io.write_out,
		hStdInput  = io.read_in,
		dwFlags    = windows.STARTF_USESTDHANDLES,
	}
	wcmd: [^]u16 = windows.utf8_to_wstring(cmd, context.temp_allocator)
	defer delete(wcmd[:len(cmd) + 1], context.temp_allocator) // <-- segfaults

	success := windows.CreateProcessW(
		nil,
		wcmd,
		nil,
		nil,
		windows.TRUE,
		windows.CREATE_NO_WINDOW,
		nil,
		nil,
		&si,
		&pi,
	)
	if !success {
		return
	} else {
		// windows.WaitForSingleObject(pi.hProcess, windows.INFINITE)
		windows.CloseHandle(pi.hProcess)
		windows.CloseHandle(pi.hThread)
		windows.CloseHandle(io.write_out)
	}
	return true
}
//
COMMTIMEOUTS :: struct {
	ReadIntervalTimeout:         windows.DWORD, /* Maximum time between read chars. */
	ReadTotalTimeoutMultiplier:  windows.DWORD, /* Multiplier of characters.        */
	ReadTotalTimeoutConstant:    windows.DWORD, /* Constant in milliseconds.        */
	WriteTotalTimeoutMultiplier: windows.DWORD, /* Multiplier of characters.        */
	WriteTotalTimeoutConstant:   windows.DWORD, /* Constant in milliseconds.        */
}
foreign import kernel32 "system:Kernel32.lib"
@(default_calling_convention = "stdcall")
foreign kernel32 {
	SetCommTimeouts :: proc(hFile: windows.HANDLE, lpCommTimeouts: ^COMMTIMEOUTS) -> windows.BOOL ---
	PeekNamedPipe :: proc(hNamedPipe: windows.HANDLE, lpBuffer: rawptr, nBufferSize: windows.DWORD, lpBytesRead: ^windows.DWORD, lpTotalBytesAvail: ^windows.DWORD, lpBytesLeftThisMessage: ^windows.DWORD) -> windows.BOOL ---
}

read_from_pipe :: proc(buf: ^[dynamic]byte, size: int, io: ^IO_Pipes) {
	// pk_len:windows.DWORD
	// PeekNamedPipe(io.read_out, nil,0,nil, &pk_len, nil)
	ct := COMMTIMEOUTS{}
	ct.ReadTotalTimeoutConstant = 0
	success: windows.BOOL
	SetCommTimeouts(io.read_out, &ct)
	last_start_index := 0
	buf_struct := transmute(^runtime.Raw_Dynamic_Array)buf
	for {
		// note: in theory size is decremented by the dw_read, and cap(buf) is decremented by the same, net no need to do?
		if cap(buf) < size {
			reserve(buf, size) // ensure we have room in our buffer before reading
		}
		dw_read: windows.DWORD = 0
		success = windows.ReadFile(
			io.read_out,
			&buf[last_start_index],
			u32(size) - 1,
			&dw_read,
			nil,
		)
		buf_struct.len += int(dw_read) // manually adjust the len of dyn arr

		if !success {break}
		last_start_index += int(dw_read)
	}
}
