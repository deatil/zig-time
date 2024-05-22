const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const time = std.time;

pub const Location = struct {
    offset: i32,

    pub fn utc() Location {
        return Location{
            .offset = 0,
        };
    }
};

pub const Time = struct {
    const Self = @This();
    
    ns: i128,
    loc: Location,

    pub fn fromNanoTimestamp(t: i128) Time {
        const loc = Location.utc();
        
        return Time{
            .ns = t,
            .loc = loc,
        };
    }

    pub fn timestamp(self: Self) i128 {
        return @divFloor(self.milliTimestamp(), time.ms_per_s);
    }
    
    pub fn milliTimestamp(self: Self) i64 {
        return @as(i64, @intCast(@divFloor(self.ns, time.ns_per_ms)));
    }
    
    pub fn microTimestamp(self: Self) i64 {
        return @as(i64, @intCast(@divFloor(self.ns, time.ns_per_us)));
    }
    
    pub fn nanoTimestamp(self: Self) i128 {
        return self.ns;
    }

    pub fn isZero(self: Self) bool {
        return self.nanoTimestamp() == 0;
    }

    pub fn equal(self: Self, other: Self) bool {
        return self.nanoTimestamp() == other.nanoTimestamp();
    }
};

// now time
pub fn now() Time {
    const ts = time.nanoTimestamp();
    return Time.fromNanoTimestamp(ts);
}

test "now" {
    const margin = time.ns_per_ms * 50;

    // std.debug.print("{d}", .{now().milliTimestamp()});

    const time_0 = now().milliTimestamp();
    time.sleep(time.ns_per_ms);
    const time_1 = now().milliTimestamp();
    const interval = time_1 - time_0;
    
    try testing.expect(interval > 0);

    const now_t = now();
    try testing.expect(now_t.timestamp() > 0);
    try testing.expect(now_t.milliTimestamp() > 0);
    try testing.expect(now_t.microTimestamp() > 0);
    try testing.expect(now_t.nanoTimestamp() > 0);
    
    // Tests should not depend on timings: skip test if outside margin.
    if (!(interval < margin)) return error.SkipZigTest;
}

test "equal" {
    const ii_0: i128 = 1691879007511594906;
    const ii_1: i128 = 1691879007511594907;

    const time_0 = Time.fromNanoTimestamp(ii_0);
    const time_1 = Time.fromNanoTimestamp(ii_0);
    const time_2 = Time.fromNanoTimestamp(ii_1);

    try testing.expect(time_0.equal(time_1));
    try testing.expect(!time_0.equal(time_2));
}

test "isZero" {
    const ii_0: i128 = 1691879007511594906;
    const ii_1: i128 = 0;

    const time_0 = Time.fromNanoTimestamp(ii_0);
    const time_1 = Time.fromNanoTimestamp(ii_1);

    try testing.expect(!time_0.isZero());
    try testing.expect(time_1.isZero());
}

