const std = @import("std");
const heap = std.heap;
const http = std.http;
const fs = std.fs;
const File = fs.File;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const builtin = @import("builtin");

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

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 4) {
        try stderr.print("Usage: fetch <year> <day> <output_path>\n", .{});
        try stderr.flush();
        std.process.exit(1);
    }

    const year = args[1];
    const day = args[2];
    const output_path = args[3];

    // Skip if file already exists
    if (fs.cwd().access(output_path, .{})) |_| return else |_| {}

    const session_token = std.process.getEnvVarOwned(allocator, "AOC_SESSION_TOKEN") catch {
        try stderr.print("AOC_SESSION_TOKEN environment variable not found\n", .{});
        try stderr.flush();
        std.process.exit(1);
    };
    defer allocator.free(session_token);

    const content = fetchInput(threaded.io(), allocator, year, day, session_token) catch |err| {
        try stderr.print("Failed to fetch input: {}\n", .{err});
        try stderr.flush();
        std.process.exit(1);
    };
    defer allocator.free(content);

    const dir = try fs.cwd().makeOpenPath(fs.path.dirname(output_path).?, .{});
    const file = try dir.createFile(fs.path.basename(output_path), .{});
    defer file.close();
    try file.writeAll(content);
}

fn fetchInput(io: Io, allocator: Allocator, year: []const u8, day: []const u8, session_token: []const u8) ![]const u8 {
    var http_client: http.Client = .{ .io = io, .allocator = allocator };
    defer http_client.deinit();

    var response: Io.Writer.Allocating = .init(allocator);
    errdefer response.deinit();

    const url = try std.fmt.allocPrint(
        allocator,
        "https://adventofcode.com/{s}/day/{s}/input",
        .{ year, day },
    );
    defer allocator.free(url);

    const cookie = try std.fmt.allocPrint(allocator, "session={s}", .{session_token});
    defer allocator.free(cookie);

    const res = try http_client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .extra_headers = &.{.{
            .name = "Cookie",
            .value = cookie,
        }},
        .response_writer = &response.writer,
    });

    if (res.status != .ok) return error.FailedToFetchInputFile;

    return try response.toOwnedSlice();
}

const BUFFER_SIZE = 4 * 1024;

var stderr_buffer: [BUFFER_SIZE]u8 = undefined;
var stderr_writer = File.stderr().writer(&stderr_buffer);
const stderr = &stderr_writer.interface;
