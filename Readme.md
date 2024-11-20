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
AOC_SESSION_TOKEN="<TOKEN>"
```  

You can pass the command line flags `-Dyear=<year>` and `-Dday=<day>` 
to specify the year and day you want to generate the template for 
(if you don't pass them, it will default to the current year and day of the month).

```sh
zig build --build-runner build_runner.zig -Dyear=2023 -Dday=1 --watch run
```

You can pass `test` instead of run to run the unit tests instead:
```sh
zig build --build-runner build_runner.zig -Dyear=2023 -Dday=1 --watch run
```

## Details

When you run the build command for a year and day for the first time,
it generates the source code template (`./src/<year>/<day>.zig`) and input 
(`./input/<year>/<day>.txt`) for that year/day. 

The `./src/<year>/<day>.zig` file will have the following format:

```zig
const std = @import("std");
const mem = std.mem;

input: []const u8,
allocator: mem.Allocator,

pub fn part1(this: *const @This()) !?i64 {
    _ = this;
    return null;
}

pub fn part2(this: *const @This()) !?i64 {
    _ = this;
    return null;
}

test "it should do nothing" {
    const allocator = std.testing.allocator;
    const input = "";

    const problem: @This() = .{
        .input = input,
        .allocator = allocator,
    };

    try std.testing.expectEqual(null, try problem.part1());
    try std.testing.expectEqual(null, try problem.part2());
}
```

You "solve" the problem by returning the solution from `part1` and `part2` function.
The `input` field is the input data for the problem (see `build.zig` and `src/main.zig` 
for details on how this is achieved).

Add tests for small examples and edge cases in tests blocks at the end of the file.
