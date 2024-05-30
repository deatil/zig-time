## Zig-time 

zig-time is a time lib.


### Env

 - Zig >= 0.12


### Get Starting

~~~zig
const std = @import("std");
const time = @import("zig-time");

pub fn main() !void {
    const time_0 = time.now().timestamp();
    std.debug.print("now time: {d} \n", .{time_0});
    
    // ==========
    
    const seed: i64 = 1691879007;
    const fmt: []const u8 = "YYYY-MM-DD HH:mm:ss z";
    
    const alloc = std.heap.page_allocator;
    const instant = time.Time.fromTimestamp(seed).setLoc(time.UTC);
    const fmtRes = try instant.formatAlloc(alloc, fmt);
    defer alloc.free(fmtRes);
    
    // output: 
    // format time: 2023-08-12 22:23:27 UTC
    std.debug.print("format time: {s} \n", .{fmtRes});
}
~~~


### LICENSE

*  The library LICENSE is `Apache2`, using the library need keep the LICENSE.


### Copyright

*  Copyright deatil(https://github.com/deatil).
