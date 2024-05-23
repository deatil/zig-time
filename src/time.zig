const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const time = std.time;
const epoch = time.epoch;

pub const Location = struct {
    offset: i32,

    pub fn utc() Location {
        return Location{
            .offset = 0,
        };
    }

    // offset is hour
    pub fn fixed(offset: i32) Location {
        const new_offset = offset * time.s_per_hour;
        
        return Location{
            .offset = new_offset,
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

    pub fn setLoc(self: Self, loc: Location) Self {
        var cp = self;

        cp.ns = self.ns;
        cp.loc = loc;
        return cp;
    }

    // return timestamp
    
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

    // for format time output

    fn unixSec(self: Self) i64 {
        return @divTrunc(@as(isize, @intCast(self.ns)), time.ns_per_s);
    }

    pub fn unix(self: Self) i64 {
        return self.unixSec();
    }

    fn nsec(self: Self) i32 {
        if (self.ns == 0) {
            return 0;
        }
        
        return @as(i32, @intCast((self.ns - (self.unixSec() * time.ns_per_s)) & nsec_mask));
    }
    
    fn abs(self: Self) u64 {
        var usec = self.unixSec();
        usec += @as(i64, @intCast(self.loc.offset));

        const ov = @addWithOverflow(usec, unix_to_internal + internal_to_absolute);
        const result: i64 = ov[0];

        return @as(u64, @bitCast(result));
    }
      
    pub fn date(self: Self) DateDetail {
        return absDate(self.abs(), true);
    }
    
    pub fn year(self: Self) epoch.Year {
        const d = self.date();
        return @as(epoch.Year, @intCast(d.year));
    }

    pub fn month(self: Self) epoch.Month {
        const d = self.date();
        return d.month;
    }

    pub fn day(self: Self) u9 {
        const d = self.date();
        return @as(u9, @intCast(d.day));
    }

    pub fn hour(self: Self) u5 {
        const d = @divTrunc(@as(isize, @intCast(self.abs() % seconds_per_day)), seconds_per_hour);
        return @as(u5, @intCast(d));
    }

    pub fn minute(self: Self) u6 {
        const d = @divTrunc(@as(isize, @intCast(self.abs() % seconds_per_hour)), seconds_per_minute);
        return @as(u6, @intCast(d));
    }

    pub fn second(self: Self) u6 {
        const d = @as(isize, @intCast(self.abs() % seconds_per_minute));
        return @as(u6, @intCast(d));
    }

    /// returns the nanosecond offset within the second specified by self,
    /// in the range [0, 999999999].
    pub fn nanosecond(self: Self) isize {
        return @as(isize, @intCast(self.nsec()));
    }
};

const nsec_mask: u64 = (1 << 30) - 1;

const daysBefore = [_]isize{
    0,
    31,
    31 + 28,
    31 + 28 + 31,
    31 + 28 + 31 + 30,
    31 + 28 + 31 + 30 + 31,
    31 + 28 + 31 + 30 + 31 + 30,
    31 + 28 + 31 + 30 + 31 + 30 + 31,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30 + 31,
};

const seconds_per_minute = 60;
const seconds_per_hour = 60 * seconds_per_minute;
const seconds_per_day = 24 * seconds_per_hour;
const seconds_per_week = 7 * seconds_per_day;
const days_per_400_years = 365 * 400 + 97;
const days_per_100_years = 365 * 100 + 24;
const days_per_4_years = 365 * 4 + 1;
const absolute_zero_year: i64 = -292277022399;

// The year of the zero Time.
// Assumed by the unix_to_internal computation below.
const internal_year: i64 = 1;

const unix_to_internal: i64 = (1969 * 365 + 1969 / 4 - 1969 / 100 + 1969 / 400) * seconds_per_day;
const internal_to_unix: i64 = -unix_to_internal;

// Offsets to convert between internal and absolute or Unix times.
const absolute_to_internal: i64 = (absolute_zero_year - internal_year) * @as(i64, @intFromFloat(365.2425 * @as(f64, @floatFromInt(seconds_per_day))));
const internal_to_absolute = -absolute_to_internal;

pub const DateDetail = struct {
    year: isize,
    month: epoch.Month,
    day: isize,
    yday: isize,
};

fn absDate(abs: u64, full: bool) DateDetail {
    var details: DateDetail = undefined;
    // Split into time and day.
    var d = abs / seconds_per_day;

    // Account for 400 year cycles.
    var n = d / days_per_400_years;
    var y = 400 * n;
    d -= days_per_400_years * n;

    // Cut off 100-year cycles.
    // The last cycle has one extra leap year, so on the last day
    // of that year, day / days_per_100_years will be 4 instead of 3.
    // Cut it back down to 3 by subtracting n>>2.
    n = d / days_per_100_years;
    n -= n >> 2;
    y += 100 * n;
    d -= days_per_100_years * n;

    // Cut off 4-year cycles.
    // The last cycle has a missing leap year, which does not
    // affect the computation.
    n = d / days_per_4_years;
    y += 4 * n;
    d -= days_per_4_years * n;

    // Cut off years within a 4-year cycle.
    // The last year is a leap year, so on the last day of that year,
    // day / 365 will be 4 instead of 3. Cut it back down to 3
    // by subtracting n>>2.
    n = d / 365;
    n -= n >> 2;
    y += n;
    d -= 365 * n;
    details.year = @as(isize, @intCast(@as(i64, @intCast(y)) + absolute_zero_year));
    details.yday = @as(isize, @intCast(d));
    if (!full) {
        return details;
    }
    
    details.day = details.yday;
    if (epoch.isLeapYear(@as(epoch.Year, @intCast(details.year)))) {
        if (details.day > (31 + 29 - 1)) {
            // After leap day; pretend it wasn't there.
            details.day -= 1;
        } else if (details.day == (31 + 29 - 1)) {
            // Leap day.
            details.month = epoch.Month.feb;
            details.day = 29;
            return details;
        }
    }

    // Estimate month on assumption that every month has 31 days.
    // The estimate may be too low by at most one month, so adjust.
    var month = @as(usize, @intCast(details.day)) / @as(usize, 31);
    const end = daysBefore[month + 1];
    var begin: isize = 0;
    if (details.day >= end) {
        month += 1;
        begin = end;
    } else {
        begin = daysBefore[month];
    }
    
    month += 1;
    details.day = details.day - begin + 1;
    details.month = @as(epoch.Month, @enumFromInt(month));
    return details;
}

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

test "format show" {
    const ii_0: i128 = 1691879007511594906;

    const time_0 = Time.fromNanoTimestamp(ii_0).setLoc(Location.fixed(8));

    try testing.expectFmt("1691879007", "{d}", .{time_0.unix()});
    try testing.expectFmt("2023", "{d}", .{time_0.year()});
    try testing.expectFmt("8", "{d}", .{time_0.month().numeric()});
    try testing.expectFmt("13", "{d}", .{time_0.day()});
    try testing.expectFmt("6", "{d}", .{time_0.hour()});
    try testing.expectFmt("23", "{d}", .{time_0.minute()});
    try testing.expectFmt("27", "{d}", .{time_0.second()});
    try testing.expectFmt("511594906", "{d}", .{time_0.nanosecond()});
}
