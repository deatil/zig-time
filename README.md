## Zig-time 

zig-time is a time lib.


### Env

 - Zig >= 0.12


### Get Starting

~~~zig
const std = @import("std");
const time = @import("zig-time");

pub fn main() !void {
    const time_0 = now().timestamp();
    
    std.debug.print("now time: {d}\n", .{time_0});
}
~~~


### LICENSE

*  The library LICENSE is `Apache2`, using the library need keep the LICENSE.


### Copyright

*  Copyright deatil(https://github.com/deatil).
