const std = @import("std");
const st = @import("state.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub fn processMouseEvent(state: *st.State, bytes: []u8) !void {
    // NOTE: for now it only handles mouse wheel events
    // TODO: handle click mouse events
    if (bytes[0] == 27 and bytes[1] == '[' and bytes[2] == '<') {
        std.debug.print("mouse event: {}\r\n", .{bytes[3]});
        if (bytes[4] == 52) {
            state.moveCursorUp(10);
        }
        if (bytes[4] == 53) {
            state.moveCursorDown(10);
        }
    }
}

// helper function for mouse events, not yet all implemented
pub fn handleMouseEvent(button: u8, x: u8, y: u8) !void {
    switch (button) {
        0 => { // Left click
            try ui.moveCursorTo(x, y);
        },
        1 => { // Middle click
        },
        2 => { // Right click
        },
        64 => { // Scroll up
            try ui.moveCursorUp(3);
        },
        65 => { // Scroll down
            try ui.moveCursorDown(3);
        },
        else => {},
    }
}

pub fn handleSingleByteReplace(state: *st.State) !void {
    state.mode = .replace_mode;
    try ui.drawUi();

    // replace mode: get next keystroke to determine byte value
    var replacement_bytes: [6]u8 = undefined;
    const read_count_l = try std.io.getStdIn().reader().read(&replacement_bytes);

    const original_replacement_value = state.tmpHex.items[state.selected_byte_index];

    if (read_count_l > 0) {
        const change = st.Change{
            .address = state.selected_byte_index,
            .old_value = original_replacement_value,
            .new_value = replacement_bytes[0],
            .kind = .replace,
        };

        // handle hex input (0-9, a-f)
        if (utils.isHexDigit(replacement_bytes[0])) {
            var hex_input: [2]u8 = undefined;
            hex_input[0] = replacement_bytes[0];

            // if first char is a hex digit, try to read a second hex digit
            const second_read_count = try std.io.getStdIn().reader().read(&replacement_bytes);
            if (second_read_count > 0 and utils.isHexDigit(replacement_bytes[0])) {
                hex_input[1] = replacement_bytes[0];
            } else {
                // if no second digit, use 0 as the second digit
                hex_input[1] = '0';
            }

            // convert two-digit hex to byte
            if (std.fmt.parseInt(u8, &hex_input, 16)) |byte_value| {
                state.tmpHex.items[state.selected_byte_index] = byte_value;

                // save the replacement in the changes array list
                try state.changes.append(change);
            } else |_| {
                // parsing error, do nothing
                return;
            }
        }
        // optionally handle direct character input if desired
        else if (utils.isValidChar(replacement_bytes[0])) {
            // convert printable character to its ascii value
            state.tmpHex.items[state.selected_byte_index] = replacement_bytes[0];

            // save the replacement in the changes array list
            try state.changes.append(change);
        }

        state.mode = .normal_mode;

        // redraw ui to reflect the change
        try ui.drawUi();
    }
}

pub fn handleUndo(state: *st.State) !void {
    // pop the last change and restore the byte value
    if (state.changes.popOrNull()) |pop| {
        switch (pop.kind) {
            .insert => {
                // remove the inserted byte
                _ = state.tmpHex.orderedRemove(pop.address);
                state.selected_byte_index = pop.address;

                // move the cursor to the left if we're at the end of the buffer
                if (state.selected_byte_index == state.tmpHex.items.len) {
                    state.moveCursorLeft(1);
                }
            },
            .remove => {
                // try testing.expect(pop.key == i - 1 and pop.value == i - 1);
                state.selected_byte_index = pop.address;

                state.tmpHex.insertSlice(pop.address, &[_]u8{pop.old_value}) catch {};
                try ui.drawUi();
            },
            .replace => {
                // try testing.expect(pop.key == i - 1 and pop.value == i - 1);
                state.selected_byte_index = pop.address;
                state.tmpHex.items[state.selected_byte_index] = pop.old_value;
            },
        }
    }
    try ui.drawUi();
}

pub fn handleDelete(state: *st.State) !void {
    // bounds checking
    if (state.tmpHex.items.len == 0 or state.selected_byte_index >= state.tmpHex.items.len) {
        return;
    }

    // remove item at selected index
    const change = st.Change{
        .address = state.selected_byte_index,
        .old_value = state.tmpHex.orderedRemove(state.selected_byte_index),
        .new_value = 0,
        .kind = .remove,
    };
    try state.changes.append(change);

    // move the cursor to the left if we're at the end of the buffer
    if (state.selected_byte_index == state.tmpHex.items.len) {
        state.moveCursorLeft(1);
    } else {
        try ui.drawUi();
    }
}

fn handleInsert(state: *st.State) !void {
    // add a 00 byte at the cursor position
    state.tmpHex.insertSlice(state.selected_byte_index, &[_]u8{0}) catch {};
    state.mode = .insert_mode;

    const original_replacement_value = state.tmpHex.items[state.selected_byte_index];

    ui.drawUi() catch {
        _ = state.tmpHex.orderedRemove(state.selected_byte_index);
        return;
    };

    // get the byte to insert
    var replacement_bytes: [1]u8 = undefined;
    const read_count_l = try std.io.getStdIn().reader().read(&replacement_bytes);

    if (read_count_l > 0) {
        const change = st.Change{
            .address = state.selected_byte_index,
            .old_value = original_replacement_value,
            .new_value = replacement_bytes[0],
            .kind = .insert,
        };

        // handle hex input (0-9, a-f)
        if (utils.isHexDigit(replacement_bytes[0])) {
            var hex_input: [2]u8 = undefined;
            hex_input[0] = replacement_bytes[0];

            // if first char is a hex digit, try to read a second hex digit
            const second_read_count = try std.io.getStdIn().reader().read(&replacement_bytes);
            if (second_read_count > 0 and utils.isHexDigit(replacement_bytes[0])) {
                hex_input[1] = replacement_bytes[0];
            } else {
                // if no second digit, use 0 as the second digit
                hex_input[1] = '0';
            }

            // convert two-digit hex to byte
            if (std.fmt.parseInt(u8, &hex_input, 16)) |byte_value| {
                state.tmpHex.replaceRange(state.selected_byte_index, 1, &[_]u8{byte_value}) catch {
                    _ = state.tmpHex.orderedRemove(state.selected_byte_index);
                    return;
                };

                // save the replacement in the changes array list
                try state.changes.append(change);
            } else |_| {
                // parsing error, do nothing
                return;
            }
        } else if (utils.isValidChar(replacement_bytes[0])) {
            // convert printable character to its ascii value
            state.tmpHex.replaceRange(state.selected_byte_index, 1, &[_]u8{replacement_bytes[0]}) catch {
                _ = state.tmpHex.orderedRemove(state.selected_byte_index);
                return;
            };

            // save the replacement in the changes array list
            try state.changes.append(change);
        }

        // redraw ui to reflect the change
        try ui.drawUi();
    }

    // move the cursor to the left if we're at the end of the buffer
    if (state.selected_byte_index == state.tmpHex.items.len) {
        state.moveCursorLeft(1);
    }

    state.mode = .normal_mode;
    try ui.drawUi();
}

fn handleWriteToFile(state: *st.State) !void {
    // get the file name from the state
    const file_name = state.file_name;

    // save the changes to the file, recreate it
    var file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    try file.writeAll(state.tmpHex.items);

    std.debug.print("Wrote to file: {s}\n", .{file_name});
}

pub fn handleInput(state: *st.State) !bool {
    const stdin = std.io.getStdIn().reader();
    var bytes: [6]u8 = undefined;
    const read_count = try stdin.read(&bytes);

    if (read_count == 6 and bytes[0] == 27 and bytes[1] == '[' and bytes[2] == '<') {
        try processMouseEvent(state, bytes[0..6]);
    }

    // at the top of your file, add the sequence you're looking for
    const RESIZE_SEQUENCE = "\x1b[<t".*; // \x1b is escape character (27)

    // then in handleinput:
    if (read_count >= 4 and std.mem.containsAtLeast(u8, bytes[0..read_count], 1, &RESIZE_SEQUENCE)) {
        // terminal was resized
        try ui.drawUi();
        return false;
    }

    switch (bytes[0]) {
        // q
        'q' => {
            try ui.deinit();
            // exit the program
            return true;
        },
        // vim-style movement
        'h' => state.moveCursorLeft(1),
        'j' => state.moveCursorDown(1),
        'k' => state.moveCursorUp(1),
        'l' => state.moveCursorRight(1),
        'e' => {
            state.endianness = if (state.endianness == .little) .big else .little;
            ui.drawUi() catch {};
        },
        'r' => {
            try handleSingleByteReplace(ui.state);
        },
        'i' => {
            try handleInsert(ui.state);
        },
        'u' => {
            try handleUndo(ui.state);
        },
        'x' => {
            try handleDelete(ui.state);
        },
        'w' => {
            handleWriteToFile(ui.state) catch |err| {
                std.debug.print("Error writing to file: {}\n", .{err});
            };
        },
        // canc key
        0x1B => {
            if (bytes[1] == '[') {
                switch (bytes[2]) {
                    'A' => state.moveCursorUp(1), // Up arrow
                    'B' => state.moveCursorDown(1), // Down arrow
                    'C' => state.moveCursorRight(1), // Right arrow
                    'D' => state.moveCursorLeft(1), // Left arrow
                    // page up/down
                    '5' => {
                        if (bytes[3] == '~') {
                            state.moveCursorUp(20); // Page Up
                        }
                    },
                    '6' => {
                        if (bytes[3] == '~') {
                            state.moveCursorDown(20); // Page Down
                        }
                    },
                    // delete key
                    '3' => {
                        try handleDelete(ui.state);
                    },
                    0x31 => state.moveCursorToStart(), // Home
                    0x34 => state.moveCursorToEnd(), // End
                    else => {
                        std.debug.print("key not handled: {} {} {} {} {} {} {x} {s}\r\n", .{ bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes, bytes });
                    },
                }
            } else {
                // return error.Escape;
            }
        },
        else => {},
    }

    try ui.drawUi();

    return false;
}
