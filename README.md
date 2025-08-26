## Zig-time 

A date and time parse and format library for Zig.


### Env

 - Zig >= 0.15.1


### Adding zig-time as a dependency

Add the dependency to your project:

```sh
zig fetch --save=zig-time git+https://github.com/deatil/zig-time#main
```

or use local path to add dependency at `build.zig.zon` file

```zig
.{
    .dependencies = .{
        .@"zig-time" = .{
            .path = "./lib/zig-time",
        },
        ...
    },
    ...
}
```

And the following to your `build.zig` file:

```zig
const zig_time_dep = b.dependency("zig-time", .{});
exe.root_module.addImport("zig-time", zig_time_dep.module("zig-time"));
```

The `zig-time` structure can be imported in your application with:

```zig
const zig_time = @import("zig-time");
```


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
