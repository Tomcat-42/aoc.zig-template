const std = @import("std");
const fs = std.fs;
const fmt = std.fmt;
const Build = std.Build;
const Step = Build.Step;
const builtin = @import("builtin");

comptime {
    const required_zig = "0.16.0-dev";
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse(required_zig) catch @compileError("Failed to parse required zig version");
    if (current_zig.order(min_zig) == .lt) {
        const error_message =
            \\Sorry, it looks like your version of zig is too old. :-(
            \\
            \\aoc.zig requires development build {}
            \\
            \\Please download a development ("master") build from
            \\
            \\https://ziglang.org/download/
            \\
            \\
        ;
        @compileError(std.fmt.comptimePrint(error_message, .{min_zig}));
    }
}

pub fn build(b: *Build) !void {
    const default_year, const default_day = timestampToYearAndDay(
        (try std.Io.Clock.now(.real, b.graph.io)).toSeconds(),
        -5, // AoC is in EST
    );

    const year = b.option(
        []const u8,
        "year",
        "The year of the Advent of Code challenge",
    ) orelse try fmt.allocPrint(b.allocator, "{d}", .{default_year});

    const day = b.option(
        []const u8,
        "day",
        "The day of the Advent of Code challenge",
    ) orelse try fmt.allocPrint(b.allocator, "{d}", .{default_day});

    // Setup Step:
    // - File -> ./input/{year}/{day}.txt. If not exist on disk, fetch from AoC API, save to disk.
    // - File -> ./src/{year}/{day}.zig. If not exist on disk, create new file with template.
    const setup = try SetupStep.create(b, year, day);

    // Modules and Deps
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const problem = b.createModule(.{
        .imports = &.{.{
            .name = "util",
            .module = b.createModule(.{
                .root_source_file = b.path("src/util.zig"),
                .target = target,
                .optimize = optimize,
            }),
        }},
        .root_source_file = b.path(setup.problem_path),
        .target = target,
        .optimize = optimize,
    });

    const input = b.createModule(.{
        .root_source_file = b.path(setup.input_path),
        .target = target,
        .optimize = optimize,
    });

    const problem_test = b.addTest(.{
        .root_module = problem,
        .use_llvm = true,
        .use_lld = true,
    });

    const problem_check = b.addLibrary(.{ .name = "problem_check", .root_module = problem });

    const aoc = b.addExecutable(.{
        .name = "aoc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/aoc.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "problem", .module = problem },
                .{ .name = "input", .module = input },
            },
        }),
    });

    // Setup
    const setup_step = b.step("setup", "Fetch inputs and create source files for the requested year and day");
    aoc.step.dependOn(&setup.step);
    setup_step.dependOn(&setup.step);

    // install
    b.installArtifact(aoc);
    b.installArtifact(problem_test);

    // Run
    const run_cmd = b.addRunArtifact(aoc);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test
    const run_problem_test = b.addRunArtifact(problem_test);
    const test_step = b.step("test", "Run problem test");
    problem_test.step.dependOn(&setup.step);
    test_step.dependOn(&run_problem_test.step);

    // Clean
    const clean_step = b.step("clean", "Remove build artifacts");
    clean_step.dependOn(&b.addRemoveDirTree(b.path(fs.path.basename(b.install_path))).step);
    if (builtin.os.tag != .windows)
        clean_step.dependOn(&b.addRemoveDirTree(b.path(".zig-cache")).step);

    // Check
    const check_step = b.step("check", "Check that the build artifacts are up-to-date");
    check_step.dependOn(&setup.step);
    check_step.dependOn(&problem_check.step);
}

const INPUT_DIR = "input";
const SRC_DIR = "src";

const SetupStep = struct {
    step: Step,
    year: []const u8,
    day: []const u8,
    problem_path: []const u8,
    input_path: []const u8,

    const TEMPLATE =
        \\const std = @import("std");
        \\const Allocator = std.mem.Allocator;
        \\const Io = std.Io;
        \\
        \\pub fn part1(io: Io, allocator: Allocator, input: []const u8) !?i64 {
        \\    _ = .{ io, allocator, input };
        \\    return null;
        \\}
        \\
        \\pub fn part2(io: Io, allocator: Allocator, input: []const u8) !?i64 {
        \\    _ = .{ io, allocator, input };
        \\    return null;
        \\}
        \\
        \\test "it should do nothing" {
        \\    const io = std.testing.io;
        \\    const allocator = std.testing.allocator;
        \\    const input =
        \\        \\
        \\    ;
        \\
        \\    try std.testing.expectEqual(null, try part1(io, allocator, input));
        \\    try std.testing.expectEqual(null, try part2(io, allocator, input));
        \\}
    ;

    pub fn create(b: *Build, year: []const u8, day: []const u8) !*SetupStep {
        const problem_path = try fs.path.join(b.allocator, &.{
            SRC_DIR,
            year,
            try fmt.allocPrint(b.allocator, "day{s}.zig", .{day}),
        });

        const input_path = try fs.path.join(b.allocator, &.{
            INPUT_DIR,
            year,
            try fmt.allocPrint(b.allocator, "day{s}.txt", .{day}),
        });

        const fetch = b.addExecutable(.{
            .name = "fetch",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/fetch.zig"),
                .target = b.graph.host,
            }),
        });
        const run_fetch = b.addRunArtifact(fetch);
        run_fetch.addArgs(&.{ year, day, input_path });

        const self = b.allocator.create(SetupStep) catch @panic("OOM");
        self.* = .{
            .step = Step.init(.{
                .id = .custom,
                .name = "setup",
                .owner = b,
                .makeFn = make,
            }),
            .year = year,
            .day = day,
            .problem_path = problem_path,
            .input_path = input_path,
        };
        self.step.dependOn(&run_fetch.step);
        return self;
    }

    fn make(step: *Step, _: Step.MakeOptions) !void {
        const self: *SetupStep = @fieldParentPtr("step", step);
        try self.generateSourceFileIfNotPresent();
    }

    fn generateSourceFileIfNotPresent(self: *SetupStep) !void {
        fs.cwd().access(self.problem_path, .{}) catch {
            const dir = try fs.cwd().makeOpenPath(fs.path.dirname(self.problem_path).?, .{});
            const file = try dir.createFile(fs.path.basename(self.problem_path), .{});
            defer file.close();
            try file.writeAll(TEMPLATE);
        };
    }
};

fn timestampToYearAndDay(timestamp: i64, tz_offset_hours: i64) struct { i64, i64 } {
    const secs_per_day = 86400;
    const days_in_month = [12]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    var days = @divFloor(timestamp + tz_offset_hours * 3600, secs_per_day);
    var year: i64 = 1970;

    while (true) : (year += 1) {
        const days_in_year: i64 = if (isLeapYear(year)) 366 else 365;
        if (days < days_in_year) break;
        days -= days_in_year;
    }

    var day_of_month = days + 1;
    for (days_in_month, 0..) |days_in_m, month| {
        const dim: i64 = days_in_m + @intFromBool(month == 1 and isLeapYear(year));
        if (day_of_month <= dim) break;
        day_of_month -= dim;
    }

    return .{ year, day_of_month };
}

fn isLeapYear(year: i64) bool {
    const y: u64 = @intCast(year);
    return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0);
}
