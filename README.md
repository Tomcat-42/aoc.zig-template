# aoc.zig-template

This is a zig template for Advent of Code. It has a very opinionated structure
and automatic input fetching/source code template generation for a current year/day.
All of this is powered by the **zig build system**.

## Usage

Clone this template repo:

```bash
gh repo create aoc.zig --template Tomcat-42/aoc.zig-template --public --clone
```

Then Login to your [Advent of Code](https://adventofcode.com/) account to get your session
token. You can do that by opening the browser devtools, selecting the networks tab, reloading
the page, selecting any request and looking for the `Cookie: session=<TOKEN>` header:

![image](https://github.com/user-attachments/assets/8ee0e200-1e00-451d-8309-3a18d94ed3af)

Then, make it available as an env var:

```bash
export AOC_SESSION_TOKEN="<TOKEN>"
```

You can pass the command line flags `-Dyear=<year>` and `-Dday=<day>`
to specify the year and day you want to generate the template for
(if you don't pass them, it will default to the current year and day of the month).

```sh
zig build run -Dyear=2024 -Dday=1
```

You can pass `test` instead of run to run the unit tests instead:
```sh
zig build test -Dyear=2024 -Dday=1
```

## Details

When you run the build command for a year and day for the first time,
it generates the source code template (`./src/<year>/day<day>.zig`) and input
(`./input/<year>/day<day>.txt`) for that year/day.

The `./src/<year>/day<day>.zig` file will have the following format:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn part1(io: Io, allocator: Allocator, input: []const u8) !?i64 {
    _ = .{ io, allocator, input };
    return null;
}

pub fn part2(io: Io, allocator: Allocator, input: []const u8) !?i64 {
    _ = .{ io, allocator, input };
    return null;
}

test "it should do nothing" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const input =
        \\
    ;

    try std.testing.expectEqual(null, try part1(io, allocator, input));
    try std.testing.expectEqual(null, try part2(io, allocator, input));
}
```

You "solve" the problem by returning the solution from `part1` and `part2` function.
The `input` parameter is the input data for the problem (see `build.zig` and `src/aoc.zig`
for details on how this is achieved). Note that you can return anything as the solution,
for instance, if the solution is a string, you can return a `[]const u8` from any part.

Add tests for small examples and edge cases in tests blocks at the end of the file.
