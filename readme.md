# CMD Process Runner

This package is intended as a holdover until core:process is completed. it allows running `cmd /c THE_COMMAND` and returns an allocated dynamic array.

```odin
main :: proc() {
	data, err := cmd("odin version", true, 128)
	fmt.print(string(data[:]))
}
```
Prints:
```text
odin version dev-2023-06:a820246f

```