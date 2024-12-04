const std = @import("std");

pub const bytes_per_row = 16;

pub const ChangeKind = enum { insert, remove, replace };
pub const Mode = enum { normal_mode, replace_mode, insert_mode };

// structs to keep track of the changes
pub const Change = struct {
    address: usize,
    old_value: u8,
    new_value: u8,
    kind: ChangeKind,
};

// state struct: keep track of the application state
pub const State = struct {
    allocator: std.mem.Allocator,
    file_name: []const u8,
    tmpHex: std.ArrayListAligned(u8, null),
    terminal_rows_to_display: usize, // number of rows available for hex display
    begin_of_hex_to_display: usize, // byte offset of the viewport
    end_of_hex_to_display: usize, // byte offset of the viewport
    endianness: std.builtin.Endian,
    selected_byte_index: usize, // byte offset of the selected byte
    changes: std.ArrayList(Change), // array list that contains the byte offset and the corresponding byte value previous to the replacement
    mode: Mode,

    pub fn moveCursorUp(self: *State, n: usize) void {
        self.selected_byte_index = if (self.selected_byte_index >= 16 * n)
            self.selected_byte_index -| 16 * n
        else
            0;
    }

    pub fn moveCursorDown(self: *State, n: usize) void {
        self.selected_byte_index = if (self.selected_byte_index + (16 * n) < self.tmpHex.items.len)
            std.math.add(usize, self.selected_byte_index, 16 * n) catch self.tmpHex.items.len -| 1
        else
            self.tmpHex.items.len -| 1;
    }

    pub fn moveCursorLeft(self: *State, n: usize) void {
        self.selected_byte_index = if (self.selected_byte_index + n > self.tmpHex.items.len)
            self.tmpHex.items.len -| 1
        else if (self.selected_byte_index > 0)
            self.selected_byte_index -| 1
        else
            return;
    }

    pub fn moveCursorRight(self: *State, _: usize) void {
        self.selected_byte_index = if (self.selected_byte_index + 1 < self.tmpHex.items.len)
            self.selected_byte_index +| 1
        else
            self.selected_byte_index;
    }

    // helper function for moving cursor to start of data
    pub fn moveCursorToStart(
        self: *State,
    ) void {
        self.selected_byte_index = 0;
    }

    // helper function for moving cursor to end of data
    pub fn moveCursorToEnd(
        self: *State,
    ) void {
        self.selected_byte_index = self.tmpHex.items.len -| 1;
    }
};

pub fn init(state: *State, file_name: []const u8, allocator: std.mem.Allocator) !void {
    // read the file in binary mode into a buffer
    var file = try std.fs.openFileAbsolute(file_name, .{ .mode = .read_only });
    defer file.close();
    const fileSize = try file.getEndPos();

    const buffer = try allocator.alloc(u8, fileSize);
    _ = try file.readAll(buffer);
    defer allocator.free(buffer);

    var tmp_hex = try std.ArrayListAligned(u8, 1).initCapacity(allocator, buffer.len);
    try tmp_hex.appendSlice(buffer);

    state.* = State{
        .allocator = allocator,
        .file_name = file_name,
        .terminal_rows_to_display = 0,
        .tmpHex = tmp_hex,
        .begin_of_hex_to_display = 0,
        .end_of_hex_to_display = 0,
        .endianness = .little,
        .selected_byte_index = 0,
        .changes = std.ArrayList(Change).init(allocator),
        .mode = .normal_mode,
    };
}

pub fn deinit(state: *State) void {
    state.tmpHex.deinit();
    state.changes.deinit();
}
