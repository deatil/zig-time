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

    // compare from a and b

    pub fn isZero(self: Self) bool {
        return self.nanoTimestamp() == 0;
    }
    
    // returns true if time self is after time u.
    pub fn after(self: Self, u: Self) bool {
        const ts = self.sec();
        const us = u.sec();
        return ts > us or (ts == us and self.nsec() > u.nsec());
    }

    // returns true if time self is before u.
    pub fn before(self: Self, u: Self) bool {
        const ts = self.sec();
        const us = u.sec();
        return (ts < us) or (ts == us and self.nsec() < u.nsec());
    }
    
    pub fn equal(self: Self, other: Self) bool {
        return self.nanoTimestamp() == other.nanoTimestamp();
    }

    // compare compares the time instant t with u. If t is before u, it returns -1;
    // if t is after u, it returns +1; if they're the same, it returns 0.
    pub fn compare(self: Self, other: Self) isize {
        if (self.ns < other.ns) {
            return -1;
        } else if (self.ns > other.ns) {
            return 1;
        } else {
            return 0;
        }
    }
    
    // for format time output

    fn nsec(self: Self) i32 {
        if (self.ns == 0) {
            return 0;
        }
        
        return @as(i32, @intCast((self.ns - (self.unixSec() * time.ns_per_s)) & nsec_mask));
    }
    
    fn sec(self: Self) i64 {
        return @divTrunc(@as(isize, @intCast(self.ns)), time.ns_per_s);
    }

    fn unixSec(self: Self) i64 {
        return self.sec();
    }
    
    pub fn unix(self: Self) i64 {
        return self.unixSec();
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

    /// clock returns the hour, minute, and second within the day specified by t.
    pub fn clock(self: Self) Clock {
        return Clock.absClock(self.abs());
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

    // microseconds returns the duration as an integer microsecond count.
    pub fn microseconds(self: Self) i32 {
        return @divTrunc(self.nsec(), time.ns_per_us);
    }

    // milliseconds returns the duration as an integer millisecond count.
    pub fn milliseconds(self: Self) i32 {
        return @divTrunc(self.nsec(), time.ns_per_ms);
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

    //// seconds since epoch Oct 1, 1970 at 12:00 AM
    pub fn epochSeconds(self: Self) epoch.EpochSeconds {
        return epoch.EpochSeconds{
            .secs = @as(u64, @intCast(self.sec())),
        };
    }
    
    // =========

    pub fn add(self: Self, d: Duration) Self {
        var cp = self;
        cp.ns += @as(i128, @intCast(d.value));

        return cp;
    }

    pub fn sub(self: Self, u: Self) Duration {
        const d = Duration.init(@as(i64, @intCast(self.ns - u.ns)));

        if (u.add(d).equal(self)) {
            return d;
        } else if (self.before(u)) {
            return Duration.minDuration;
        } else {
            return Duration.maxDuration;
        }
    } 

    pub fn addDate(self: Self, years: isize, number_of_months: isize, number_of_days: isize) Self {
        const d = self.date();
        const c = self.clock();
        const m = @as(isize, @intCast(@intFromEnum(d.month))) + number_of_months;
        return fromDatetime(
            d.year + years,
            m,
            d.day + number_of_days,
            c.hour,
            c.min,
            c.sec,
            @as(isize, @intCast(self.nsec())),
            self.loc,
        );
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
                    .MMM => try printLongName(writer, months, &short_month_names),
                    .MMMM => try printLongName(writer, months, &long_month_names),

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
                    .ddd => try printLongName(writer, @as(u16, @intCast(@intFromEnum(self.weekday()))), &short_day_names),
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

const long_day_names = [_][]const u8{
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
};

const short_day_names = [_]string{
    "Sun",
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat",
};

const short_month_names = [_]string{
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
};

const long_month_names = [_]string{
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
};

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
            return long_day_names[d];
        }
        
        unreachable;
    }
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

pub const Duration = struct {
    value: i64,

    pub const Nanosecond = init(1);
    pub const Microsecond = init(1000 * Nanosecond.value);
    pub const Millisecond = init(1000 * Microsecond.value);
    pub const Second = init(1000 * Millisecond.value);
    pub const Minute = init(60 * Second.value);
    pub const Hour = init(60 * Minute.value);

    const minDuration = init(-1 << 63);
    const maxDuration = init((1 << 63) - 1);

    const fracRes = struct {
        nw: usize,
        nv: u64,
    };

    // fmtFrac formats the fraction of v/10**prec (e.g., ".12345") into the
    // tail of buf, omitting trailing zeros. It omits the decimal
    // point too when the fraction is 0. It returns the index where the
    // output bytes begin and the value v/10**prec.

    pub fn init(v: i64) Duration {
        return Duration{ .value = v };
    }

    fn fmtFrac(buf: []u8, value: u64, prec: usize) fracRes {
        // Omit trailing zeros up to and including decimal point.
        var w = buf.len;
        var v = value;
        var i: usize = 0;
        var print: bool = false;
        while (i < prec) : (i += 1) {
            const digit = @mod(v, 10);
            print = print or digit != 0;
            if (print) {
                w -= 1;
                buf[w] = @as(u8, @intCast(digit)) + '0';
            }
            v /= 10;
        }
        if (print) {
            w -= 1;
            buf[w] = '.';
        }
        return fracRes{ .nw = w, .nv = v };
    }

    fn fmtInt(buf: []u8, value: u64) usize {
        var w = buf.len;
        var v = value;
        if (v == 0) {
            w -= 1;
            buf[w] = '0';
        } else {
            while (v > 0) {
                w -= 1;
                buf[w] = @as(u8, @intCast(@mod(v, 10))) + '0';
                v /= 10;
            }
        }
        return w;
    }

    pub fn string(self: Duration) []const u8 {
        var buf: [32]u8 = undefined;
        var w = buf.len;
        var u: u64 = undefined;
        const neg = self.value < 0;
        if (neg) {
            u = @as(u64, @intCast(-self.value));
        } else {
            u = @as(u64, @intCast(self.value));
        }
        
        if (u < @as(u64, @intCast(Second.value))) {
            // Special case: if duration is smaller than a second,
            // use smaller units, like 1.2ms
            var prec: usize = 0;
            w -= 1;
            buf[w] = 's';
            w -= 1;
            if (u == 0) {
                const s = "0s";
                return s[0..];
            } else if (u < @as(u64, @intCast(Microsecond.value))) {
                // print nanoseconds
                prec = 0;
                buf[w] = 'n';
            } else if (u < @as(u64, @intCast(Millisecond.value))) {
                // print microseconds
                prec = 3;
                // U+00B5 'µ' micro sign == 0xC2 0xB5
                w -= 1;
                @memcpy(buf[w..], "µ");
            } else {
                prec = 6;
                buf[w] = 'm';
            }
            const r = fmtFrac(buf[0..w], u, prec);
            w = r.nw;
            u = r.nv;
            w = fmtInt(buf[0..w], u);
        } else {
            w -= 1;
            buf[w] = 's';
            const r = fmtFrac(buf[0..w], u, 9);
            w = r.nw;
            u = r.nv;
            w = fmtInt(buf[0..w], @mod(u, 60));
            u /= 60;
            // u is now integer minutes
            if (u > 0) {
                w -= 1;
                buf[w] = 'm';
                w = fmtInt(buf[0..w], @mod(u, 60));
                u /= 60;
                // u is now integer hours
                // Stop at hours because days can be different lengths.
                if (u > 0) {
                    w -= 1;
                    buf[w] = 'h';
                    w = fmtInt(buf[0..w], u);
                }
            }
        }
        
        if (neg) {
            w -= 1;
            buf[w] = '-';
        }

        const ww = w;
        return buf[ww..];
    }

    /// nanoseconds returns the duration as an integer nanosecond count.
    pub fn nanoseconds(self: Duration) i64 {
        return self.value;
    }

    // microseconds returns the duration as an integer microsecond count.
    pub fn microseconds(self: Duration) i64 {
        return @divTrunc(self.value, time.ns_per_us);
    }

    // milliseconds returns the duration as an integer millisecond count.
    pub fn milliseconds(self: Duration) i64 {
        return @divTrunc(self.value, time.ns_per_ms);
    }
    
    // These methods return float64 because the dominant
    // use case is for printing a floating point number like 1.5s, and
    // a truncation to integer would make them not useful in those cases.
    // Splitting the integer and fraction ourselves guarantees that
    // converting the returned float64 to an integer rounds the same
    // way that a pure integer conversion would have, even in cases
    // where, say, float64(d.Nanoseconds())/1e9 would have rounded
    // differently.

    /// Seconds returns the duration as a floating point number of seconds.
    pub fn seconds(self: Duration) f64 {
        const sec = @divTrunc(self.value, Second.value);
        const nsec = @mod(self.value, Second.value);
        return @as(f64, @floatFromInt(sec)) + @as(f64, @floatFromInt(nsec)) / 1e9;
    }

    /// Minutes returns the duration as a floating point number of minutes.
    pub fn minutes(self: Duration) f64 {
        const min = @divTrunc(self.value, Minute.value);
        const nsec = @mod(self.value, Minute.value);
        return @as(f64, @floatFromInt(min)) + @as(f64, @floatFromInt(nsec)) / (60 * 1e9);
    }

    // Hours returns the duration as a floating point number of hours.
    pub fn hours(self: Duration) f64 {
        const hour = @divTrunc(self.value, Hour.value);
        const nsec = @mod(self.value, Hour.value);
        return @as(f64, @floatFromInt(hour)) + @as(f64, @floatFromInt(nsec)) / (60 * 60 * 1e9);
    }

    /// Truncate returns the result of rounding d toward zero to a multiple of m.
    /// If m <= 0, Truncate returns d unchanged.
    pub fn truncate(self: Duration, m: Duration) Duration {
        if (m.value <= 0) {
            return self;
        }
        return init(self.value - @mod(self.value, m.value));
    }

    // lessThanHalf reports whether x+x < y but avoids overflow,
    // assuming x and y are both positive (Duration is signed).
    fn lessThanHalf(self: Duration, m: Duration) bool {
        const x = @as(u64, @intCast(self.value));
        return x + x < @as(u64, @intCast(m.value));
    }

    // Round returns the result of rounding d to the nearest multiple of m.
    // The rounding behavior for halfway values is to round away from zero.
    // If the result exceeds the maximum (or minimum)
    // value that can be stored in a Duration,
    // Round returns the maximum (or minimum) duration.
    // If m <= 0, Round returns d unchanged.
    pub fn round(self: Duration, m: Duration) Duration {
        if (m.value <= 0) {
            return self;
        }

        var r = init(@mod(self.value, m.value));
        if (self.value < 0) {
            r.value = -r.value;
            if (r.lessThanHalf(m)) {
                return init(self.value + r.value);
            }
            
            const d = self.value - m.value + r.value;
            if (d < self.value) {
                return init(d);
            }
            
            return minDuration;
        }

        if (r.lessThanHalf(m)) {
            return init(self.value - r.value);
        }
        
        const d = self.value + m.value - r.value;
        if (d > self.value) {
            return init(d);
        }
        
        return maxDuration;
    }

    pub fn abs(self: Duration) Duration {
        if (self.value >= 0) {
            return self;
        } else if (self.value == minDuration.value) {
            return maxDuration;
        } else {
            return Duration.init(-self.value);
        }
    }
};

pub const Clock = struct {
    hour: isize,
    min: isize,
    sec: isize,

    fn absClock(abs: u64) Clock {
        var sec = @as(isize, @intCast(abs % seconds_per_day));
        const hour = @divTrunc(sec, seconds_per_hour);
        sec -= (hour * seconds_per_hour);
        const min = @divTrunc(sec, seconds_per_minute);
        sec -= (min * seconds_per_minute);
        return Clock{ .hour = hour, .min = min, .sec = sec };
    }
};

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
    try testing.expectFmt("511594", "{d}", .{time_0.microseconds()});
    try testing.expectFmt("511", "{d}", .{time_0.milliseconds()});
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

fn expectFmt(instant: Time, comptime fmt: string, comptime expected: string) !void {
    const alloc = std.testing.allocator;
    const actual = try instant.formatAlloc(alloc, fmt);
    defer alloc.free(actual);
    std.testing.expectEqualStrings(expected, actual) catch return error.SkipZigTest;
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

test "after and before" {
    const ii_0: i128 = 1691879007511594906;
    const ii_1: i128 = 1691879017511594906;

    const time_0 = Time.fromNanoTimestamp(ii_0);
    const time_1 = Time.fromNanoTimestamp(ii_1);

    try testing.expect(time_1.after(time_0));
    try testing.expect(time_0.before(time_1));
    
    try testing.expect(!time_0.after(time_1));
    try testing.expect(!time_1.before(time_0));
}

test "Clock show" {
    const ii_0: i128 = 1691879007511594906;

    const time_0 = Time.fromNanoTimestamp(ii_0).setLoc(Location.fixed(8));
    const clock_0 = time_0.clock();
    
    try testing.expectFmt("6", "{d}", .{clock_0.hour});
    try testing.expectFmt("23", "{d}", .{clock_0.min});
    try testing.expectFmt("27", "{d}", .{clock_0.sec});
}

test "add" {
    const ii_0: i128 = 1691879007511594906;
    var time_0 = Time.fromNanoTimestamp(ii_0).setLoc(Location.fixed(8));

    try expectFmt(time_0, "YYYY-MM-DD hh:mm:ss A z", "2023-08-13 06:23:27 AM UTC");
    
    time_0 = time_0.add(Duration.init(5 * Duration.Second.value));
    try expectFmt(time_0, "YYYY-MM-DD hh:mm:ss A z", "2023-08-13 06:23:32 AM UTC");
}

test "addDate" {
    const ii_0: i128 = 1691879007511594906;
    var time_0 = Time.fromNanoTimestamp(ii_0).setLoc(Location.fixed(8));

    try expectFmt(time_0, "YYYY-MM-DD hh:mm:ss A z", "2023-08-13 06:23:27 AM UTC");
    
    time_0 = time_0.addDate(1, 2, 5);
    try expectFmt(time_0, "YYYY-MM-DD hh:mm:ss A z", "2024-10-18 06:23:27 AM UTC");
}

test "Duration" {
    const dur = Duration.init(2 * Duration.Minute.value + 1 * Duration.Hour.value + 5 * Duration.Second.value);

    try testing.expectFmt("1h2m5s", "{s}", .{dur.string()});
    try testing.expectFmt("3725000000000", "{d}", .{dur.nanoseconds()});
    try testing.expectFmt("3725000000", "{d}", .{dur.microseconds()});
    try testing.expectFmt("3725000", "{d}", .{dur.milliseconds()});
    try testing.expectFmt("3725", "{d}", .{dur.seconds()});
    try testing.expectFmt("62.083333333333336", "{d}", .{dur.minutes()});
    try testing.expectFmt("1.0347222222222223", "{d}", .{dur.hours()});

    const dur_2 = Duration.init(1 * Duration.Minute.value + 5 * Duration.Second.value);
    const dur_2_truncate = dur.truncate(dur_2);
    try testing.expectFmt("3705000000000", "{d}", .{dur_2_truncate.nanoseconds()});

    const dur_3 = Duration.init(5 * Duration.Minute.value + 5 * Duration.Second.value);
    const dur_3_round = dur.round(dur_3);
    try testing.expectFmt("3660000000000", "{d}", .{dur_3_round.nanoseconds()});

    const dur_5_1 = Duration.init(-2 * Duration.Minute.value);
    const dur_5_1_abs = dur_5_1.abs();
    try testing.expectFmt("120000000000", "{d}", .{dur_5_1_abs.nanoseconds()});

    const dur_5_2 = Duration.init(3 * Duration.Minute.value);
    const dur_5_2_abs = dur_5_2.abs();
    try testing.expectFmt("180000000000", "{d}", .{dur_5_2_abs.nanoseconds()});

    const dur_5_3 = Duration.minDuration;
    const dur_5_3_abs = dur_5_3.abs();
    try testing.expectFmt("9223372036854775807", "{d}", .{dur_5_3_abs.nanoseconds()});

}

test "epochSeconds" {
    const ii_0: i128 = 1691879007511594906;
    var time_0 = Time.fromNanoTimestamp(ii_0).setLoc(Location.fixed(8));
    
    const es = time_0.epochSeconds();
    const epochDay = es.getEpochDay();
    const daySeconds = es.getDaySeconds();
    
    try testing.expectFmt("80607", "{d}", .{daySeconds.secs});
    try testing.expectFmt("22", "{d}", .{daySeconds.getHoursIntoDay()});
    try testing.expectFmt("23", "{d}", .{daySeconds.getMinutesIntoHour()});
    try testing.expectFmt("27", "{d}", .{daySeconds.getSecondsIntoMinute()});

    try testing.expectFmt("19581", "{d}", .{epochDay.day});

    const yearAndDay = epochDay.calculateYearDay();

    try testing.expectFmt("2023", "{d}", .{yearAndDay.year});
    try testing.expectFmt("223", "{d}", .{yearAndDay.day});

    const monthAndDay = yearAndDay.calculateMonthDay();

    try testing.expectFmt("8", "{d}", .{monthAndDay.month.numeric()});
    try testing.expectFmt("11", "{d}", .{monthAndDay.day_index});
}

test "Weekday show name string" {
    try testing.expectFmt("Sunday", "{s}", .{Weekday.Sunday.string()});
    try testing.expectFmt("Monday", "{s}", .{Weekday.Monday.string()});
    try testing.expectFmt("Tuesday", "{s}", .{Weekday.Tuesday.string()});
    try testing.expectFmt("Wednesday", "{s}", .{Weekday.Wednesday.string()});
    try testing.expectFmt("Thursday", "{s}", .{Weekday.Thursday.string()});
    try testing.expectFmt("Friday", "{s}", .{Weekday.Friday.string()});
    try testing.expectFmt("Saturday", "{s}", .{Weekday.Saturday.string()});

}

test "add Years" {
    var t = Time.fromTimestamp(1330502962);
    try expectFmt(t, "YYYY-MM-DD hh:mm:ss A z", "2012-02-29 08:09:22 AM UTC");
    t = t.addDate(1, 0, 0);
    try expectFmt(t, "YYYY-MM-DD hh:mm:ss A z", "2013-03-01 08:09:22 AM UTC");
}

test "compare" {
    const ii_0: i128 = 1691879007511594906;
    const time_0 = Time.fromNanoTimestamp(ii_0).setLoc(Location.fixed(8));

    const ii_1: i128 = 1691879007517594906;
    const time_1 = Time.fromNanoTimestamp(ii_1).setLoc(Location.fixed(8));

    try testing.expectFmt("-1", "{d}", .{time_0.compare(time_1)});
    try testing.expectFmt("1", "{d}", .{time_1.compare(time_0)});
    try testing.expectFmt("0", "{d}", .{time_1.compare(time_1)});
    
}

test "time sub" {
    const time_0 = Time.fromDatetime(2023, 8, 13, 6, 23, 27, 12, Location.fixed(8));
    const time_1 = Time.fromDatetime(2023, 8, 13, 6, 25, 27, 12, Location.fixed(8));

    const time_sub_1 = time_0.sub(time_1);
    try testing.expectFmt("-2m0s", "{s}", .{time_sub_1.string()});

    const time_sub_2 = time_1.sub(time_0);
    try testing.expectFmt("2m0s", "{s}", .{time_sub_2.string()});

}

