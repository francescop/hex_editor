const std = @import("std");
const utils = @import("utils.zig");
const st = @import("state.zig");
const input = @import("input.zig");
const assert = std.debug.assert;

var sz: std.posix.winsize = undefined;

var original_termios: std.posix.termios = undefined;
const bytes_per_row = 16;
var ttyConfig: std.io.tty.Config = undefined;

pub var state: *st.State = undefined;

// initializes the terminal ui system.
pub fn init(main_state: *st.State) !void {
    std.debug.assert(main_state != undefined);

    state = main_state;

    // verify terminal configuration
    if (std.io.getStdOut().isTty()) {
        ttyConfig = std.io.tty.detectConfig(std.io.getStdOut());
    } else {
        return error.NotATTY;
    }

    // initialize with error handling
    try enableRawMode();
    errdefer {
        if (disableRawMode()) |_| {
            // Clean shutdown
        } else |err| {
            std.debug.print("CRITICAL: Cleanup failed: {}\n", .{err});
            std.os.exit(1);
        }
    }
}

pub fn deinit() !void {
    try clearScreen();
    try disableRawMode();
}

fn clearScreen() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("\x1b[2J\x1b[H");
}

fn enableRawMode() !void {
    // verify valid file descriptor
    if (std.posix.STDIN_FILENO < 0) {
        return error.InvalidFileDescriptor;
    }

    // get current settings
    original_termios = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch |err| {
        std.debug.print("CRITICAL: Failed to get terminal attributes: {}\n", .{err});
        return err;
    };

    // create copy of original settings
    var raw = original_termios;

    raw.iflag = std.c.tc_iflag_t{
        .BRKINT = false, // disable break interrupt
        .INPCK = false, // disable parity check
        .ISTRIP = false, // disable strip parity bits
        .IXON = false, // disable software flow control
        .ICRNL = false, // disable Ctrl-M
    };

    raw.lflag = std.c.tc_lflag_t{
        .ECHO = false, // disable echo
        .ICANON = false, // disable canonical mode (line buffering)
        .ISIG = false, // disable signals (eg Ctrl-C)
        .IEXTEN = false, // disable extensions (eg Ctrl-V)
    };

    raw.oflag = std.c.tc_oflag_t{
        .OPOST = false, // disable output processing
    };

    // apply the new settings to the terminal
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
}

pub fn disableRawMode() !void {
    // restore the original terminal settings
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, original_termios) catch |err| {
        std.debug.print("Failed to disable raw mode: {}\n", .{err});
    };
}

pub fn drawUi() !void {
    // get the number of rows
    if (std.posix.system.ioctl(std.c.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&sz)) != 0) {
        std.debug.panic("failed to get number of rows\n", .{});
    }

    // terminal_rows_to_display is the number of sz.ws_row minus the number of lines used for the UI
    state.terminal_rows_to_display = sz.ws_row - 7;

    errdefer {
        disableRawMode() catch |err| {
            std.debug.print("Failed to disable raw mode: {}\n", .{err});
        };
    }

    try clearScreen();

    const viewport_size = state.terminal_rows_to_display * bytes_per_row;
    const selected_byte_row_index = state.selected_byte_index / bytes_per_row;

    // check if cursor has moved outside the current viewport window
    if (state.selected_byte_index >= state.end_of_hex_to_display or state.selected_byte_index < state.begin_of_hex_to_display) {
        // determine viewport adjustment based on cursor position
        const target_row = if (state.selected_byte_index >= state.end_of_hex_to_display)
            // if cursor is below current viewport, move down one row
            selected_byte_row_index -| (state.terminal_rows_to_display - 1)
        else if (state.selected_byte_index < state.begin_of_hex_to_display)
            // if cursor is above current viewport, move up one row
            selected_byte_row_index
        else
            // fallback (though this should not happen)
            selected_byte_row_index -| (state.terminal_rows_to_display / 2);

        // convert row numbers to byte offsets
        // each row contains bytes_per_row (16) bytes
        // this ensures viewport always starts at a row boundary
        state.begin_of_hex_to_display = target_row * bytes_per_row;

        // set the end of viewport window bytes_per_row * terminal_rows_to_display bytes
        // ahead of the start position
        state.end_of_hex_to_display = state.begin_of_hex_to_display + viewport_size;

        // if the calculated viewport would extend past the end of the data,
        // clamp it to the actual data length to prevent buffer overrun
        if (state.end_of_hex_to_display > state.tmpHex.items.len) {
            state.end_of_hex_to_display = state.tmpHex.items.len;
        }
    }

    state.end_of_hex_to_display = @min(state.begin_of_hex_to_display + viewport_size, state.tmpHex.items.len);

    const writer = std.io.getStdOut().writer();

    var code_point_bytes: [4]u8 = undefined;
    _ = try std.unicode.utf8Encode('—', &code_point_bytes);

    try printDebugInfo(writer);

    // separator
    try writer.writeBytesNTimes(&code_point_bytes, sz.ws_col - 1);
    try writer.print("\r\n", .{});

    // hex data and inspectors
    try printColumns(writer);

    // separator
    try writer.writeBytesNTimes(&code_point_bytes, sz.ws_col - 1);

    // status line
    try printStatusLine(writer);
}

// print the hex data and inspectors
fn printColumns(writer: anytype) !void {
    // get the slice of hex data we want to display
    const sliceToShow = state.tmpHex.items[state.begin_of_hex_to_display..state.end_of_hex_to_display];

    // iterate over all needed rows (either for hex or byte inspector)
    for (0..state.terminal_rows_to_display, 0..) |_, row| {
        const offset = row * 16;

        // only print hex data if we have data for this row
        if (offset < sliceToShow.len) {
            const end = @min(offset + 16, sliceToShow.len);
            const chunk = sliceToShow[offset..end];
            try printHexRow(writer, chunk, offset);
        } else {
            // print empty space to align with byte inspector
            try writer.writeByteNTimes('\t', 9);
        }

        // check if there is enough space to print the right column
        if (sz.ws_col > bytes_per_row * 2 + 40) {
            // always print byte inspector and settings inspector (right column)
            try renderRightColumn(writer, row);
        }
        try writer.print("\r\n", .{});
    }
}

fn printHexRow(writer: anytype, bytes: []u8, offset: usize) !void {
    const row_address = state.begin_of_hex_to_display + offset;

    try printRowAddress(writer, row_address);
    try printHexBytes(writer, bytes, row_address);
    try printAsciiRepresentation(writer, bytes, row_address);
}

fn printDebugInfo(writer: anytype) !void {
    try writer.print(
        "cursor: {} - selected_byte_row_index: {}, showingHex: {}..{}, changes: {}, hexLength: {}\r\n",
        .{
            state.selected_byte_index,
            state.selected_byte_index / bytes_per_row,
            state.begin_of_hex_to_display,
            state.end_of_hex_to_display,
            state.changes.items.len,
            state.tmpHex.items.len,
        },
    );
}

fn printRowAddress(writer: anytype, row_address: usize) !void {
    const isCursorInRow = state.selected_byte_index >= row_address and
        state.selected_byte_index < row_address + bytes_per_row;

    if (isCursorInRow) {
        try ttyConfig.setColor(writer, std.io.tty.Color.bold);
    }
    try writer.print("0x{x:0>8} ", .{row_address});
    try ttyConfig.setColor(writer, std.io.tty.Color.reset);
}

fn printHexBytes(writer: anytype, chunk: []const u8, row_address: usize) !void {
    for (0.., chunk) |j, byte| {
        const byte_address = row_address + j;

        if (byte_address == state.selected_byte_index) {
            try printSelectedByte(writer, byte);
        } else {
            try printNormalByte(writer, byte);
        }

        if (j % (bytes_per_row / 2) == 7) {
            try writer.print(" ", .{});
        }
    }

    // fill empty spaces if row is not complete
    if (chunk.len < bytes_per_row) {
        for (0..bytes_per_row - chunk.len) |_| {
            try writer.print("   ", .{});
        }

        if (chunk.len < bytes_per_row / 2) {
            try writer.print("  ", .{});
        }
    }
}

fn printSelectedByte(writer: anytype, byte: u8) !void {
    try ttyConfig.setColor(writer, std.io.tty.Color.white);
    switch (state.mode) {
        .normal_mode => {
            try writer.print("\x1b[0;107m\x1b[30m{x:0>2} \x1b[0m", .{byte});
        },
        .replace_mode => {
            try writer.print("\x1b[0;41m\x1b[37m{x:0>2} \x1b[0m", .{byte});
        },
        .insert_mode => {
            try writer.print("\x1b[0;42m\x1b[37m{x:0>2} \x1b[0m", .{byte});
        },
    }
}

fn printNormalByte(writer: anytype, byte: u8) !void {
    const color = switch (byte) {
        0x00 => std.io.tty.Color.reset,
        0xFF => std.io.tty.Color.blue,
        else => if (utils.isValidChar(byte))
            std.io.tty.Color.green
        else
            std.io.tty.Color.yellow,
    };
    try ttyConfig.setColor(writer, color);
    try writer.print("{x:0>2} ", .{byte});
    try ttyConfig.setColor(writer, std.io.tty.Color.reset);
}

fn printAsciiRepresentation(writer: anytype, chunk: []const u8, row_address: usize) !void {
    for (0.., chunk) |j, byte| {
        const byte_address = row_address + j;

        if (state.selected_byte_index == byte_address) {
            try ttyConfig.setColor(writer, std.io.tty.Color.bold);
        }

        if (byte == 0x00) {
            try writer.print(".", .{});
        } else if (byte == 0xFF) {
            try ttyConfig.setColor(writer, std.io.tty.Color.blue);
            try writer.print(".", .{});
        } else if (utils.isValidChar(byte)) {
            try ttyConfig.setColor(writer, std.io.tty.Color.green);
            try writer.print("{c}", .{byte});
        } else {
            try ttyConfig.setColor(writer, std.io.tty.Color.yellow);
            try writer.print(".", .{});
        }

        try ttyConfig.setColor(writer, std.io.tty.Color.reset);
    }

    // fill empty spaces if row is not complete
    if (chunk.len < bytes_per_row) {
        for (0..bytes_per_row - chunk.len) |_| {
            try writer.print(" ", .{});
        }
    }
}

fn printStatusLine(writer: anytype) !void {
    try writer.print(
        "\r\nbyte address: 0x{x:0>8}\r\n",
        .{state.selected_byte_index},
    );
}

fn renderRightColumn(writer: anytype, linenumber: usize) !void {
    try byteInspector(writer, linenumber);
    try printSettingsInspector(writer, linenumber);
}

// represent the byte at the selected byte index
pub fn byteInspector(writer: anytype, linenumber: usize) !void {
    if (state.tmpHex.items.len == 0) {
        return;
    }

    const u8_num: u8 = @intCast(state.tmpHex.items[state.selected_byte_index]);
    const i8_num: i8 = @bitCast(u8_num);

    var u16_num: ?u16 = null;
    var i16_num: ?i16 = null;
    var f16_num: ?f16 = null;

    if (state.selected_byte_index + 2 < state.tmpHex.items.len) {
        u16_num = std.mem.readInt(u16, state.tmpHex.items[state.selected_byte_index..][0..2], state.endianness);
        if (u16_num != null) {
            i16_num = @bitCast(u16_num.?);
            f16_num = @bitCast(u16_num.?);
        }
    }

    var u32_num: ?u32 = null;
    var i32_num: ?i32 = null;
    var f32_num: ?f32 = null;
    if (state.selected_byte_index + 4 < state.tmpHex.items.len) {
        u32_num = std.mem.readInt(u32, state.tmpHex.items[state.selected_byte_index..][0..4], state.endianness);
        if (u32_num != null) {
            i32_num = @bitCast(u32_num.?);
            f32_num = @bitCast(u32_num.?);
        }
    }

    var u64_num: ?u64 = null;
    var i64_num: ?i64 = null;
    if (state.selected_byte_index + 8 < state.tmpHex.items.len) {
        u64_num = std.mem.readInt(u64, state.tmpHex.items[state.selected_byte_index..][0..8], state.endianness);
        if (u64_num != null) {
            i64_num = @bitCast(u64_num.?);
        }
    }

    var u128_num: ?u128 = null;
    var i128_num: ?i128 = null;
    if (state.selected_byte_index + 16 < state.tmpHex.items.len) {
        u128_num = std.mem.readInt(u128, state.tmpHex.items[state.selected_byte_index..][0..16], state.endianness);
        if (u128_num != null) {
            i128_num = @bitCast(u128_num.?);
        }
    }

    const bool_val: bool = if (u8_num == 0) false else true;

    try writer.print("\t│ ", .{});

    switch (linenumber) {
        0 => {
            try writer.print("binary:\t{b:0>8}", .{state.tmpHex.items[state.selected_byte_index]});
        },
        1 => {
            try writer.print("uint8:\t{d}", .{u8_num});
        },
        2 => {
            try writer.print("int8:\t\t{d}", .{i8_num});
        },
        3 => {
            try writer.print("uint16:\t", .{});
            if (u16_num != null) {
                try writer.print("{d}", .{u16_num.?});
            }
        },
        4 => {
            try writer.print("int16:\t", .{});
            if (i16_num != null) {
                try writer.print("{d}", .{i16_num.?});
            }
        },
        5 => {
            try writer.print("float16:\t", .{});
            if (f16_num != null) {
                try writer.print("{d}", .{f16_num.?});
            }
        },
        6 => {
            try writer.print("uint32:\t", .{});
            if (u32_num != null) {
                try writer.print("{d}", .{u32_num.?});
            }
        },
        7 => {
            try writer.print("int32:\t", .{});
            if (i32_num != null) {
                try writer.print("{d}", .{i32_num.?});
            }
        },
        8 => {
            try writer.print("uint64:\t", .{});
            if (u64_num != null) {
                try writer.print("{d}", .{u64_num.?});
            }
        },
        9 => {
            try writer.print("int64:\t", .{});
            if (i64_num != null) {
                try writer.print("{d}", .{i64_num.?});
            }
        },
        10 => {
            try writer.print("uint128:\t", .{});
            if (u128_num != null) {
                try writer.print("{d}", .{u128_num.?});
            }
        },
        11 => {
            try writer.print("int128:\t", .{});
            if (i128_num != null) {
                try writer.print("{d}", .{i128_num.?});
            }
        },
        12 => {
            try writer.print("bool:\t\t{}", .{bool_val});
        },
        13 => {
            try writer.print("ascii:\t", .{});
            if (utils.isValidChar(state.tmpHex.items[state.selected_byte_index])) {
                try writer.print("{c}", .{state.tmpHex.items[state.selected_byte_index]});
            }
        },
        else => {},
    }
}

pub fn printSettingsInspector(writer: anytype, linenumber: usize) !void {
    if (linenumber == 14) {
        var code_point_bytes: [4]u8 = undefined;
        _ = try std.unicode.utf8Encode('—', &code_point_bytes);
        try writer.writeBytesNTimes(&code_point_bytes, sz.ws_col / 3);
    }
    if (linenumber == 15) {
        try writer.print("endianness:\t{s}", .{@tagName(state.endianness)});
    }
    if (linenumber == 17) {
        try writer.print("w: save", .{});
    }
    if (linenumber == 18) {
        try writer.print("u: undo", .{});
    }
    if (linenumber == 19) {
        try writer.print("x: delete", .{});
    }
    if (linenumber == 20) {
        try writer.print("r: replace", .{});
    }
    if (linenumber == 21) {
        try writer.print("i: insert", .{});
    }
    if (linenumber == 22) {
        try writer.print("q: quit", .{});
    }
}

pub fn run(s: *st.State) !void {
    // install cleanup handler first
    defer {
        if (disableRawMode()) |_| {
            // successful cleanup
        } else |err| {
            // log error and terminate with error status
            std.debug.print("CRITICAL: Failed to disable raw mode: {}\n", .{err});
            std.os.exit(1);
        }
    }

    // initialize ui
    if (drawUi()) |_| {
        // ui initialized successfully
    } else |err| {
        // handle initialization failure
        try disableRawMode();
        std.debug.print("CRITICAL: Failed to initialize UI: {}\n", .{err});
        return err;
    }

    // main loop
    while (true) {
        if (input.handleInput(&s.*)) |should_quit| {
            if (should_quit) break;
        } else |err| {
            std.debug.print("ERROR: Input handling failed: {}\n", .{err});
            return err;
        }
    }
}
