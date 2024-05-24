const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const string = []const u8;
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
    
    pub fn fromMicroTimestamp(t: i64) Time {
        const loc = Location.utc();
        const tt = @as(i128, @intCast(t * time.ns_per_us));
        
        return Time{
            .ns = tt,
            .loc = loc,
        };
    }
    
    pub fn fromMilliTimestamp(t: i64) Time {
        const loc = Location.utc();
        const tt = @as(i128, @intCast(t * time.ns_per_ms));
        
        return Time{
            .ns = tt,
            .loc = loc,
        };
    }
    
    pub fn fromTimestamp(t: i64) Time {
        const loc = Location.utc();
        const tt = @as(i128, @intCast(t * time.ns_per_s));
        
        return Time{
            .ns = tt,
            .loc = loc,
        };
    }

    pub fn fromDate(years: isize, months: isize, days: isize, loc: Location) Time {
        return fromDatetime(years, months, days, 0, 0, 0, 0, loc);
    }
    
    pub fn fromDatetime(
        years: isize,
        months: isize,
        days: isize,
        hours: isize,
        mins: isize,
        seces: isize,
        nseces: isize,
        loc: Location,
    ) Time {
        var v_year = years;
        var v_day = days;
        var v_hour = hours;
        var v_min = mins;
        var v_sec = seces;
        var v_nsec = nseces;

        // Normalize month, overflowing into year
        var m = months - 1;
        var r = norm(v_year, m, 12);
        v_year = r.hi;
        m = r.lo;
        const v_month = @as(epoch.Month, @enumFromInt(@as(usize, @intCast(m)) + 1));

        // Normalize nsec, sec, min, hour, overflowing into day.
        r = norm(v_sec, v_nsec, 1e9);
        v_sec = r.hi;
        v_nsec = r.lo;
        r = norm(v_min, v_sec, 60);
        v_min = r.hi;
        v_sec = r.lo;
        r = norm(v_hour, v_min, 60);
        v_hour = r.hi;
        v_min = r.lo;
        r = norm(v_day, v_hour, 24);
        v_day = r.hi;
        v_hour = r.lo;

        // Compute days since the absolute epoch.
        var d = daysSinceeEpoch(v_year);

        // Add in days before this month.
        d += @as(u64, @intCast(daysBefore[@intFromEnum(v_month) - 1]));
        if (epoch.isLeapYear(@as(epoch.Year, @intCast(v_year))) and @intFromEnum(v_month) >= @intFromEnum(epoch.Month.mar)) {
            d += 1; // February 29
        }

        // Add in days before today.
        d += @as(u64, @intCast(v_day - 1));

        // Add in time elapsed today.
        var abses = d * seconds_per_day;
        abses += @as(u64, @intCast(v_hour * seconds_per_hour + v_min * seconds_per_minute + v_sec));

        const ov = @addWithOverflow(@as(i64, @bitCast(abses)), (absolute_to_internal + internal_to_unix));
        var unix_value: i64 = ov[0];

        if (loc.offset != 0) {
            unix_value -= @as(i64, @intCast(loc.offset));
        }

        const ii: i128 = @as(i128, @intCast(unix_value)) * time.ns_per_s;
        const tt = @as(i128, @intCast(ii + @as(i128, @intCast(v_nsec))));

        return Time{
            .ns = tt,
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
    
    pub fn timestamp(self: Self) i64 {
        return @as(i64, @intCast(@divFloor(self.ns, time.ns_per_s)));
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
    pub fn nanosecond(self: Self) i32 {
        return self.nsec();
    }
    
    pub fn yearDay(self: Self) u16 {
        const d = absDate(self.abs(), false);
        return @as(u16, @intCast(d.yday)) + 1;
    }
    
    // ========
    
    /// returns the day of the week specified by self.
    pub fn weekday(self: Self) Weekday {
        return absWeekday(self.abs());
    }

    /// isoWeek returns the ISO 8601 year and week number in which self occurs.
    /// Week ranges from 1 to 53. Jan 01 to Jan 03 of year n might belong to
    /// week 52 or 53 of year n-1, and Dec 29 to Dec 31 might belong to week 1
    /// of year n+1.
    pub fn isoWeek(self: Self) ISOWeek {
        var d = self.date();
        const wday = @mod(@as(isize, @intCast(@intFromEnum(self.weekday()) + 8)), 7);
        const Mon: isize = 0;
        const Tue = Mon + 1;
        const Wed = Tue + 1;
        const Thu = Wed + 1;
        const Fri = Thu + 1;
        const Sat = Fri + 1;
        // const Sun = Sat + 1;

        // Calculate week as number of Mondays in year up to
        // and including today, plus 1 because the first week is week 0.
        // Putting the + 1 inside the numerator as a + 7 keeps the
        // numerator from being negative, which would cause it to
        // round incorrectly.
        var week = @divTrunc(d.yday - wday + 7, 7);

        // The week number is now correct under the assumption
        // that the first Monday of the year is in week 1.
        // If Jan 1 is a Tuesday, Wednesday, or Thursday, the first Monday
        // is actually in week 2.
        const jan1wday = @mod((wday - d.yday + 7 * 53), 7);

        if (Tue <= jan1wday and jan1wday <= Thu) {
            week += 1;
        }
        if (week == 0) {
            d.year -= 1;
            week = 52;
        }

        // A year has 53 weeks when Jan 1 or Dec 31 is a Thursday,
        // meaning Jan 1 of the next year is a Friday
        // or it was a leap year and Jan 1 of the next year is a Saturday.
        if (jan1wday == Fri or (jan1wday == Sat) and epoch.isLeapYear(@as(epoch.Year, @intCast(d.year)))) {
            week += 1;
        }

        // December 29 to 31 are in week 1 of next year if
        // they are after the last Thursday of the year and
        // December 31 is a Monday, Tuesday, or Wednesday.
        if (@intFromEnum(d.month) == @intFromEnum(epoch.Month.dec) and d.day >= 29 and wday < Thu) {
            const dec31wday = @mod((wday + 31 - d.day), 7);
            if (Mon <= dec31wday and dec31wday <= Wed) {
                d.year += 1;
                week = 1;
            }
        }

        return ISOWeek{ .year = d.year, .week = week };
    }

    // =========
    
    /// fmt is based on https://momentjs.com/docs/#/displaying/format/
    pub fn format(self: Self, comptime fmt: string, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (fmt.len == 0) {
            @compileError("DateTime: format string can't be empty");
        }

        @setEvalBranchQuota(100000);

        const d = self.date();

        const years = @as(u16, @intCast(d.year));
        const months = d.month.numeric() - 1;
        const days = @as(u8, @intCast(d.day));

        const hours = self.hour();
        const minutes = self.minute();
        const seconds = self.second();
        const ms = @as(u16, @intCast(@divTrunc(self.nanosecond(), time.ns_per_ms)));
        
        comptime var s = 0;
        comptime var e = 0;
        comptime var next: ?FormatSeq = null;
        inline for (fmt, 0..) |c, i| {
            e = i + 1;

            if (comptime std.meta.stringToEnum(FormatSeq, fmt[s..e])) |tag| {
                next = tag;
                if (i < fmt.len - 1) continue;
            }

            if (next) |tag| {
                switch (tag) {
                    .MM => try writer.print("{:0>2}", .{months + 1}),
                    .M => try writer.print("{}", .{months + 1}),
                    .Mo => try printOrdinal(writer, months + 1),
                    .MMM => try printLongName(writer, months, &[_]string{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }),
                    .MMMM => try printLongName(writer, months, &[_]string{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }),

                    .Q => try writer.print("{}", .{months / 3 + 1}),
                    .Qo => try printOrdinal(writer, months / 3 + 1),

                    .D => try writer.print("{}", .{days}),
                    .Do => try printOrdinal(writer, days),
                    .DD => try writer.print("{:0>2}", .{days}),

                    .DDD => try writer.print("{}", .{self.yearDay()}),
                    .DDDo => try printOrdinal(writer, self.yearDay()),
                    .DDDD => try writer.print("{:0>3}", .{self.yearDay()}),

                    .d => try writer.print("{}", .{@intFromEnum(self.weekday())}),
                    .do => try printOrdinal(writer, @as(u16, @intCast(@intFromEnum(self.weekday())))),
                    .dd => try writer.writeAll(@tagName(self.weekday())[0..2]),
                    .ddd => try printLongName(writer, @as(u16, @intCast(@intFromEnum(self.weekday()))), &[_]string{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }),
                    .dddd => try writer.writeAll(@tagName(self.weekday())),
                    .e => try writer.print("{}", .{@intFromEnum(self.weekday())}),
                    .E => try writer.print("{}", .{@intFromEnum(self.weekday()) + 1}),

                    .w => try writer.print("{}", .{self.yearDay() / 7}),
                    .wo => try printOrdinal(writer, self.yearDay() / 7),
                    .ww => try writer.print("{:0>2}", .{self.yearDay() / 7}),

                    .Y => try writer.print("{}", .{years + 10000}),
                    .YY => try writer.print("{:0>2}", .{years % 100}),
                    .YYY => try writer.print("{}", .{years}),
                    .YYYY => try writer.print("{:0>4}", .{years}),

                    .A => try printLongName(writer, hours / 12, &[_]string{ "AM", "PM" }),
                    .a => try printLongName(writer, hours / 12, &[_]string{ "am", "pm" }),

                    .H => try writer.print("{}", .{hours}),
                    .HH => try writer.print("{:0>2}", .{hours}),
                    .h => try writer.print("{}", .{wrap(hours, 12)}),
                    .hh => try writer.print("{:0>2}", .{wrap(hours, 12)}),
                    .k => try writer.print("{}", .{wrap(hours, 24)}),
                    .kk => try writer.print("{:0>2}", .{wrap(hours, 24)}),

                    .m => try writer.print("{}", .{minutes}),
                    .mm => try writer.print("{:0>2}", .{minutes}),

                    .s => try writer.print("{}", .{seconds}),
                    .ss => try writer.print("{:0>2}", .{seconds}),

                    .S => try writer.print("{}", .{ms / 100}),
                    .SS => try writer.print("{:0>2}", .{ms / 10}),
                    .SSS => try writer.print("{:0>3}", .{ms}),

                    .z => try writer.writeAll("UTC"),
                    .Z => try writer.writeAll("+00:00"),
                    .ZZ => try writer.writeAll("+0000"),

                    .x => try writer.print("{}", .{self.milliTimestamp()}),
                    .X => try writer.print("{}", .{self.timestamp()}),
                }
                next = null;
                s = i;
            }

            switch (c) {
                ',',
                ' ',
                ':',
                '-',
                '.',
                'T',
                'W',
                '/',
                => {
                    try writer.writeAll(&.{c});
                    s = i + 1;
                    continue;
                },
                else => {},
            }
        }
    }

    pub fn formatAlloc(self: Self, alloc: std.mem.Allocator, comptime fmt: string) !string {
        var list = std.ArrayList(u8).init(alloc);
        defer list.deinit();

        try self.format(fmt, .{}, list.writer());
        return list.toOwnedSlice();
    }

    const FormatSeq = enum {
        M, // 1 2 ... 11 12
        Mo, // 1st 2nd ... 11th 12th
        MM, // 01 02 ... 11 12
        MMM, // Jan Feb ... Nov Dec
        MMMM, // January February ... November December
        Q, // 1 2 3 4
        Qo, // 1st 2nd 3rd 4th
        D, // 1 2 ... 30 31
        Do, // 1st 2nd ... 30th 31st
        DD, // 01 02 ... 30 31
        DDD, // 1 2 ... 364 365
        DDDo, // 1st 2nd ... 364th 365th
        DDDD, // 001 002 ... 364 365
        d, // 0 1 ... 5 6
        do, // 0th 1st ... 5th 6th
        dd, // Su Mo ... Fr Sa
        ddd, // Sun Mon ... Fri Sat
        dddd, // Sunday Monday ... Friday Saturday
        e, // 0 1 ... 5 6 (locale)
        E, // 1 2 ... 6 7 (ISO)
        w, // 1 2 ... 52 53
        wo, // 1st 2nd ... 52nd 53rd
        ww, // 01 02 ... 52 53
        Y, // 11970 11971 ... 19999 20000 20001 (Holocene calendar)
        YY, // 70 71 ... 29 30
        YYY, // 1 2 ... 1970 1971 ... 2029 2030
        YYYY, // 0001 0002 ... 1970 1971 ... 2029 2030
        A, // AM PM
        a, // am pm
        H, // 0 1 ... 22 23
        HH, // 00 01 ... 22 23
        h, // 1 2 ... 11 12
        hh, // 01 02 ... 11 12
        k, // 1 2 ... 23 24
        kk, // 01 02 ... 23 24
        m, // 0 1 ... 58 59
        mm, // 00 01 ... 58 59
        s, // 0 1 ... 58 59
        ss, // 00 01 ... 58 59
        S, // 0 1 ... 8 9 (second fraction)
        SS, // 00 01 ... 98 99
        SSS, // 000 001 ... 998 999
        z, // EST CST ... MST PST
        Z, // -07:00 -06:00 ... +06:00 +07:00
        ZZ, // -0700 -0600 ... +0600 +0700
        x, // unix milli
        X, // unix
    };
};

pub const format = struct {
    pub const LT = "h:mm A";
    pub const LTS = "h:mm:ss A";
    pub const L = "MM/DD/YYYY";
    pub const l = "M/D/YYY";
    pub const LL = "MMMM D, YYYY";
    pub const ll = "MMM D, YYY";
    pub const LLL = LL ++ " " ++ LT;
    pub const lll = ll ++ " " ++ LT;
    pub const LLLL = "dddd, " ++ LLL;
    pub const llll = "ddd, " ++ lll;
};

fn daysSinceeEpoch(year: isize) u64 {
    var y = @as(u64, @intCast(@as(i64, @intCast(year)) - absolute_zero_year));

    // Add in days from 400-year cycles.
    var n = @divTrunc(y, 400);
    y -= (400 * n);
    var d = days_per_400_years * n;

    // Add in 100-year cycles.
    n = @divTrunc(y, 100);
    y -= 100 * n;
    d += days_per_100_years * n;

    // Add in 4-year cycles.
    n = @divTrunc(y, 4);
    y -= 4 * n;
    d += days_per_4_years * n;

    // Add in non-leap years.
    n = y;
    d += 365 * n;

    return d;
}

pub const Weekday = enum(usize) {
    Sunday,
    Monday,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,

    pub fn string(self: Weekday) []const u8 {
        const d = @intFromEnum(self);
        if (@intFromEnum(Weekday.Sunday) <= d and d <= @intFromEnum(Weekday.Saturday)) {
            return weekdays[d];
        }
        unreachable;
    }
};

const weekdays = [_]string{
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
};

/// ISO 8601 year and week number
pub const ISOWeek = struct {
    year: isize,
    week: isize,
};

fn absWeekday(abs: u64) Weekday {
    const s = @mod(abs + @as(u64, @intCast(@intFromEnum(Weekday.Monday))) * seconds_per_day, seconds_per_week);
    const w = s / seconds_per_day;
    return @as(Weekday, @enumFromInt(@as(usize, @intCast(w))));
}

const normRes = struct {
    hi: isize,
    lo: isize,
};

// norm returns nhi, nlo such that
//  hi * base + lo == nhi * base + nlo
//  0 <= nlo < base

fn norm(i: isize, o: isize, base: isize) normRes {
    var hi = i;
    var lo = o;
    if (lo < 0) {
        const n = @divTrunc(-lo - 1, base) + 1;
        hi -= n;
        lo += (n * base);
    }
    if (lo >= base) {
        const n = @divTrunc(lo, base);
        hi += n;
        lo -= (n * base);
    }
    return normRes{ .hi = hi, .lo = lo };
}

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

fn printOrdinal(writer: anytype, num: u16) !void {
    try writer.print("{}", .{num});
    try writer.writeAll(switch (num) {
        1 => "st",
        2 => "nd",
        3 => "rd",
        else => "th",
    });
}

fn printLongName(writer: anytype, index: u16, names: []const string) !void {
    try writer.writeAll(names[index]);
}

fn wrap(val: u16, at: u16) u16 {
    const tmp = val % at;
    return if (tmp == 0) at else tmp;
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

    try testing.expectFmt("1691879007", "{d}", .{time_0.timestamp()});
    try testing.expectFmt("1691879007511", "{d}", .{time_0.milliTimestamp()});
    try testing.expectFmt("1691879007511594", "{d}", .{time_0.microTimestamp()});
    try testing.expectFmt("1691879007511594906", "{d}", .{time_0.nanoTimestamp()});

    try testing.expectFmt("1691879007", "{d}", .{time_0.unix()});
    try testing.expectFmt("2023", "{d}", .{time_0.year()});
    try testing.expectFmt("8", "{d}", .{time_0.month().numeric()});
    try testing.expectFmt("13", "{d}", .{time_0.day()});
    try testing.expectFmt("6", "{d}", .{time_0.hour()});
    try testing.expectFmt("23", "{d}", .{time_0.minute()});
    try testing.expectFmt("27", "{d}", .{time_0.second()});
    try testing.expectFmt("511594906", "{d}", .{time_0.nanosecond()});
    try testing.expectFmt("225", "{d}", .{time_0.yearDay()});
}

test "from time" {
    const ii_0: i64 = 1691879007511594;
    const time_0 = Time.fromMicroTimestamp(ii_0).setLoc(Location.fixed(8));
    try testing.expectFmt("1691879007511594000", "{d}", .{time_0.nanoTimestamp()});

    const ii_1: i64 = 1691879007511;
    const time_1 = Time.fromMilliTimestamp(ii_1).setLoc(Location.fixed(8));
    try testing.expectFmt("1691879007511000000", "{d}", .{time_1.nanoTimestamp()});

    const ii_2: i64 = 1691879007;
    const time_2 = Time.fromMilliTimestamp(ii_2).setLoc(Location.fixed(8));
    try testing.expectFmt("1691879007000000", "{d}", .{time_2.nanoTimestamp()});
}

test "fromDatetime" {
    const time_0 = Time.fromDatetime(2023, 8, 13, 6, 23, 27, 12, Location.fixed(8));
    try testing.expectFmt("1691879007000000012", "{d}", .{time_0.nanoTimestamp()});
}

test "fromDate" {
    const time_0 = Time.fromDate(2023, 8, 13, Location.fixed(8));
    try testing.expectFmt("1691856000000000000", "{d}", .{time_0.nanoTimestamp()});
}

test "weekday" {
    const ii_0: i64 = 1691879007511594;
    const time_0 = Time.fromMicroTimestamp(ii_0).setLoc(Location.fixed(8));
    try testing.expectFmt("Sunday", "{s}", .{time_0.weekday().string()});
}

test "ISOWeek" {
    const ii_0: i64 = 1691879007511594;
    const time_0 = Time.fromMicroTimestamp(ii_0).setLoc(Location.fixed(8));
    try testing.expectFmt("2023", "{d}", .{time_0.isoWeek().year});
    try testing.expectFmt("33", "{d}", .{time_0.isoWeek().week});
}

fn testCase(comptime seed: i64, comptime fmt: string, comptime expected: string) type {
    return struct {
        test "format" {
            const alloc = std.testing.allocator;
            const instant = Time.fromMilliTimestamp(seed);
            const actual = try instant.formatAlloc(alloc, fmt);
            defer alloc.free(actual);
            std.testing.expectEqualStrings(expected, actual) catch return error.SkipZigTest;
        }
    };
}

fn testHarness(comptime seed: i64, comptime expects: []const [2]string) void {
    for (0..expects.len) |i| {
        const exp = expects[i];
        _ = testCase(seed, exp[0], exp[1]);
    }
}

comptime {
    testHarness(1691879007511, &.{
        .{ "YYYY-MM-DD HH:mm:ss", "2023-08-12 22:23:27" },
    });

    testHarness(0, &.{.{ "YYYY-MM-DD HH:mm:ss", "1970-01-01 00:00:00" }});
    testHarness(1257894000000, &.{.{ "YYYY-MM-DD HH:mm:ss", "2009-11-10 23:00:00" }});
    testHarness(1634858430000, &.{.{ "YYYY-MM-DD HH:mm:ss", "2021-10-21 23:20:30" }});
    testHarness(1634858430023, &.{.{ "YYYY-MM-DD HH:mm:ss.SSS", "2021-10-21 23:20:30.023" }});
    testHarness(1144509852789, &.{.{ "YYYY-MM-DD HH:mm:ss.SSS", "2006-04-08 15:24:12.789" }});

    testHarness(1635033600000, &.{
        .{ "H", "0" },  .{ "HH", "00" },
        .{ "h", "12" }, .{ "hh", "12" },
        .{ "k", "24" }, .{ "kk", "24" },
    });

    testHarness(1635037200000, &.{
        .{ "H", "1" }, .{ "HH", "01" },
        .{ "h", "1" }, .{ "hh", "01" },
        .{ "k", "1" }, .{ "kk", "01" },
    });

    testHarness(1635076800000, &.{
        .{ "H", "12" }, .{ "HH", "12" },
        .{ "h", "12" }, .{ "hh", "12" },
        .{ "k", "12" }, .{ "kk", "12" },
    });
    testHarness(1635080400000, &.{
        .{ "H", "13" }, .{ "HH", "13" },
        .{ "h", "1" },  .{ "hh", "01" },
        .{ "k", "13" }, .{ "kk", "13" },
    });

    testHarness(1144509852789, &.{
        .{ "M", "4" },
        .{ "Mo", "4th" },
        .{ "MM", "04" },
        .{ "MMM", "Apr" },
        .{ "MMMM", "April" },

        .{ "Q", "2" },
        .{ "Qo", "2nd" },

        .{ "D", "8" },
        .{ "Do", "8th" },
        .{ "DD", "08" },

        .{ "DDD", "98" },
        .{ "DDDo", "98th" },
        .{ "DDDD", "098" },

        .{ "d", "6" },
        .{ "do", "6th" },
        .{ "dd", "Sa" },
        .{ "ddd", "Sat" },
        .{ "dddd", "Saturday" },
        .{ "e", "6" },
        .{ "E", "7" },

        .{ "w", "14" },
        .{ "wo", "14th" },
        .{ "ww", "14" },

        .{ "Y", "12006" },
        .{ "YY", "06" },
        .{ "YYY", "2006" },
        .{ "YYYY", "2006" },

        .{ "A", "PM" },
        .{ "a", "pm" },

        .{ "H", "15" },
        .{ "HH", "15" },
        .{ "h", "3" },
        .{ "hh", "03" },
        .{ "k", "15" },
        .{ "kk", "15" },

        .{ "m", "24" },
        .{ "mm", "24" },

        .{ "s", "12" },
        .{ "ss", "12" },

        .{ "S", "7" },
        .{ "SS", "78" },
        .{ "SSS", "789" },

        .{ "z", "UTC" },
        .{ "Z", "+00:00" },
        .{ "ZZ", "+0000" },

        .{ "x", "1144509852789" },
        .{ "X", "1144509852" },

        .{ format.LT, "3:24 PM" },
        .{ format.LTS, "3:24:12 PM" },
        .{ format.L, "04/08/2006" },
        .{ format.l, "4/8/2006" },
        .{ format.LL, "April 8, 2006" },
        .{ format.ll, "Apr 8, 2006" },
        .{ format.LLL, "April 8, 2006 3:24 PM" },
        .{ format.lll, "Apr 8, 2006 3:24 PM" },
        .{ format.LLLL, "Saturday, April 8, 2006 3:24 PM" },
        .{ format.llll, "Sat, Apr 8, 2006 3:24 PM" },
    });

    testHarness(1144509852789, &.{.{ "YYYYMM", "200604" }});
 
}
