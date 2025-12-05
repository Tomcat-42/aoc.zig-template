const std = @import("std");
const heap = std.heap;
const fs = std.fs;
const File = fs.File;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const builtin = @import("builtin");

const problem = @import("problem");

pub fn main() !void {
    var debug_allocator: heap.DebugAllocator(.{}) = .init;
    const allocator = switch (builtin.mode) {
        .Debug, .ReleaseSafe => debug_allocator.allocator(),
        else => heap.smp_allocator,
    };
    defer switch (builtin.mode) {
        .Debug, .ReleaseSafe => assert(debug_allocator.deinit() == .ok),
        else => {},
    };

    var threaded: Io.Threaded = .init(allocator);
    defer threaded.deinit();
    const io = threaded.io();

    const input = @embedFile("input");

    if (try problem.part1(io, allocator, input)) |solution| try stdout.print(
        switch (@TypeOf(solution)) {
            []const u8 => "{s}\n",
            else => "{any}\n",
        },
        .{solution},
    );

    if (try problem.part2(io, allocator, input)) |solution| try stdout.print(
        switch (@TypeOf(solution)) {
            []const u8 => "{s}\n",
            else => "{any}\n",
        },
        .{solution},
    );

    try stdout.flush();
}

const BUFFER_SIZE = 64 * 1024;

var stdout_buffer: [BUFFER_SIZE]u8 = undefined;
var stdout_writer = File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;
