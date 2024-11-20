const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const http = std.http;
const builtin = @import("builtin");
const fmt = std.fmt;

const Build = std.Build;
const LazyPath = Build.LazyPath;
const Step = Build.Step;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

var YEAR: []const u8 = undefined;
var DAY: []const u8 = undefined;
const INPUT_DIR = "input";
const SRC_DIR = "src";

pub fn build(b: *Build) !void {
    // Targets
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "aoc.zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Year and day comptime selection
    const date = timestampToYearAndDay(
        std.time.timestamp(),
        -5, // AoC is in EST
    );
    YEAR = b.option(
        []const u8,
        "year",
        "The year of the Advent of Code challenge",
    ) orelse try fmt.allocPrint(b.allocator, "{d}", .{date.year});
    DAY = b.option(
        []const u8,
        "day",
        "The day of the Advent of Code challenge",
    ) orelse try fmt.allocPrint(b.allocator, "{d}", .{date.day});
    // const options = b.addOptions();
    // options.addOption([]const u8, "YEAR", YEAR);
    // options.addOption([]const u8, "DAY", DAY);
    // options.addOption([]const u8, "INPUT_DIR", INPUT_DIR);
    // exe.root_module.addOptions("config", options);
    exe.root_module.addAnonymousImport(
        "problem",
        .{
            .root_source_file = b.path(
                try fs.path.join(
                    b.allocator,
                    &[_][]const u8{
                        SRC_DIR,
                        YEAR,
                        try fmt.allocPrint(
                            b.allocator,
                            "day{s}.zig",
                            .{DAY},
                        ),
                    },
                ),
            ),
        },
    );
    exe.root_module.addAnonymousImport(
        "input",
        .{
            .root_source_file = b.path(
                try fs.path.join(
                    b.allocator,
                    &[_][]const u8{
                        INPUT_DIR,
                        YEAR,
                        try fmt.allocPrint(
                            b.allocator,
                            "day{s}.txt",
                            .{DAY},
                        ),
                    },
                ),
            ),
        },
    );

    // Setup Step:
    // - File -> ./input/{year}/{day}.txt. If not exist on disk, fetch from AoC API, save to disk, and then read.
    // - File -> ./src/{year}/{day}.zig. If not exist on disk, Create new file with template `assets/template.zig`.
    const setup_step = b.step(
        "setup",
        "Fetch inputs and create source files for the requested year and day",
    );
    setup_step.makeFn = setup;
    exe.step.dependOn(setup_step);

    // install
    b.installArtifact(exe);

    // run
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // test
    const problem_unit_tests = b.addTest(.{
        .root_source_file = b.path(
            try fs.path.join(
                b.allocator,
                &[_][]const u8{
                    SRC_DIR,
                    YEAR,
                    try fmt.allocPrint(
                        b.allocator,
                        "day{s}.zig",
                        .{DAY},
                    ),
                },
            ),
        ),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(problem_unit_tests);
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    // clean
    const clean_step = b.step("clean", "Remove build artifacts");
    clean_step.dependOn(&b.addRemoveDirTree(b.path(fs.path.basename(b.install_path))).step);

    // in windows, you cannot delete a running executable 😥
    if (builtin.os.tag != .windows)
        clean_step.dependOn(&b.addRemoveDirTree(b.path(".zig-cache")).step);
}

fn setup(s: *Build.Step, o: Build.Step.MakeOptions) !void {
    // NOTE: Might use those guys later for caching purposes.
    _ = o;
    _ = s;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    fetchInputFileIfNotPresent(allocator) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            print("AOC_SESSION_TOKEN environment variable not found, you need to set it to fetch input files from AoC Server.\n", .{});
            std.process.exit(1);
        },
        error.FailedToFetchInputFile => {
            print("Failed to fetch input file from AoC Server (Has the problem already been released?).\n", .{});
            std.process.exit(1);
        },
        else => {
            print("Error: {}\n", .{err});
            std.process.exit(1);
        },
    };

    try generateSourceFileIfNotPresent(allocator);
}

fn fetchInputFileIfNotPresent(allocator: Allocator) !void {
    const input_path = try fs.path.join(
        allocator,
        &[_][]const u8{
            INPUT_DIR,
            YEAR,
            try fmt.allocPrint(
                allocator,
                "day{s}.txt",
                .{DAY},
            ),
        },
    );

    // If file is already present, return the path
    if (fs.cwd().access(input_path, .{})) |_| {
        return;
    } else |_| { // Else, fetch from AoC API, save to disk, and then return the path
        const session_token = try std.process.getEnvVarOwned(
            allocator,
            "AOC_SESSION_TOKEN",
        );

        var http_client = http.Client{
            .allocator = allocator,
        };
        defer http_client.deinit();

        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();

        const res = try http_client.fetch(.{
            .location = .{
                .url = try fmt.allocPrint(
                    allocator,
                    "https://adventofcode.com/{s}/day/{s}/input",
                    .{ YEAR, DAY },
                ),
            },
            .method = .GET,
            .extra_headers = &[_]http.Header{
                .{
                    .name = "Cookie",
                    .value = try fmt.allocPrint(
                        allocator,
                        "session={s}",
                        .{session_token},
                    ),
                },
            },
            .response_storage = .{ .dynamic = &response },
        });

        if (res.status != .ok) 
            return error.FailedToFetchInputFile;

        // Save to disk
        const dir = try fs.cwd().makeOpenPath(
            fs.path.dirname(input_path).?,
            .{},
        );
        const file = try dir.createFile(fs.path.basename(input_path), .{});
        defer file.close();
        try file.writeAll(response.items);
    }
}

fn generateSourceFileIfNotPresent(allocator: Allocator) !void {
    const src_path = try fs.path.join(
        allocator,
        &[_][]const u8{
            SRC_DIR,
            YEAR,
            try fmt.allocPrint(
                allocator,
                "day{s}.zig",
                .{DAY},
            ),
        },
    );

    // If file is already present, do nothing
    if (fs.cwd().access(src_path, .{})) |_| {
        return;
    } else |_| { // Else, create new file with template
        const template =
            \\const std = @import("std");
            \\const mem = std.mem;
            \\
            \\input: []const u8,
            \\allocator: mem.Allocator,
            \\
            \\pub fn part1(this: *const @This()) !?i64 {
            \\    _ = this;
            \\    return null;
            \\}
            \\
            \\pub fn part2(this: *const @This()) !?i64 {
            \\    _ = this;
            \\    return null;
            \\}
            \\
            \\test "it should do nothing" {
            \\    const allocator = std.testing.allocator;
            \\    const input = "";
            \\
            \\    const problem: @This() = .{
            \\        .input = input,
            \\        .allocator = allocator,
            \\    };
            \\
            \\    try std.testing.expectEqual(null, try problem.part1());
            \\    try std.testing.expectEqual(null, try problem.part2());
            \\}
        ;
        const dir = try fs.cwd().makeOpenPath(
            fs.path.dirname(src_path).?,
            .{},
        );
        const file = try dir.createFile(fs.path.basename(src_path), .{});
        defer file.close();
        try file.writeAll(template);
    }
}

// Zig std lib doesn't have DateTime yet, so I had to roll my own abomination.
inline fn isLeapYear(year: i64) bool {
    return (@mod(year, 4) == 0 and @mod(year, 100) != 0) or (@mod(year, 400) == 0);
}

fn timestampToYearAndDay(timestamp: i64, timezoneOffsetHours: i64) struct { year: i64, day: i64 } {
    var year: i64 = 1970;
    const secondsInNormalYear: i64 = 31536000; // 365 days
    const secondsInLeapYear: i64 = 31622400; // 366 days

    // Adjust timestamp for timezone offset
    const adjustedTimestamp: i64 = timestamp + timezoneOffsetHours * 3600;

    // Calculate the year
    var remainingSeconds = adjustedTimestamp;
    while (true) {
        const secondsInYear = if (isLeapYear(year)) secondsInLeapYear else secondsInNormalYear;
        if (remainingSeconds < secondsInYear) break;
        remainingSeconds -= secondsInYear;
        year += 1;
    }

    // Calculate the day of the year
    const secondsPerDay: i64 = 24 * 60 * 60;
    var dayOfYear = @as(i64, @divTrunc(remainingSeconds, secondsPerDay)) + 1;
    remainingSeconds = @mod(remainingSeconds, secondsPerDay);

    // Calculate the month and day of the month
    const daysInMonth: [2][12]u8 = .{
        // Normal year
        .{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
        // Leap year
        .{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
    };

    const leapIndex: usize = if (isLeapYear(year)) 1 else 0;
    var monthIndex: usize = 0;

    while (dayOfYear > @as(i64, daysInMonth[leapIndex][monthIndex])) {
        dayOfYear -= @as(i64, daysInMonth[leapIndex][monthIndex]);
        monthIndex += 1;
    }

    // Return the year and day of the month
    return .{ .year = year, .day = dayOfYear };
}
