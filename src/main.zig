const std = @import("std");
const c_termios = @cImport(@cInclude("termios.h"));
const utils = @import("utils.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");
const st = @import("state.zig");

const bytes_per_row = 16;

pub fn main() !void {
    // set allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpaAllocator = gpa.allocator();
    defer _ = gpa.deinit();

    // parse args into string array (error union needs 'try')
    const args = try std.process.argsAlloc(gpaAllocator);
    defer std.process.argsFree(gpaAllocator, args);

    // get the file name from the args
    const fileName = args[1];

    var state: st.State = undefined;
    try st.init(&state, fileName, gpaAllocator);

    // Ensure raw mode is disabled on normal exit
    defer {
        st.deinit(&state);
    }

    try ui.init(&state);
    try ui.run(&state);
}
