# Terminal Hex Editor

![screenshot](/screenshot.png?raw=true)

A lightweight, dependency-free terminal-based hex editor written in Zig.

## Features

- View and edit binary files in hexadecimal format
- Insert, replace, and delete bytes
- Undo functionality
- Save modifications to the original file
- Toggle between little and big endian

## Installation

1. Ensure you have Zig compiler installed
2. Clone the repository
3. Compile with: `zig build-exe src/main.zig`

## Usage

```bash
./hex-editor [filename]
```

### Keyboard Controls

- `h,j,k,l`: Navigate left, down, up, right
- `i`: Insert mode
- `r`: Replace byte
- `x`: Delete byte
- `u`: Undo last action
- `w`: Write changes to file
- `e`: Toggle endianness
- `q`: Quit editor

### Navigation Keys

- Arrow keys: Move cursor
- Page Up/Down: Scroll quickly
- Home/End: Jump to start/end of file

## Dependencies

- Zig standard library
- POSIX terminal control (termios)

## TODO

- [ ] address range selection
- [ ] address lookup
