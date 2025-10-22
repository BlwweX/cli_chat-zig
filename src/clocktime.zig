const std = @import("std");
const c = @cImport(@cInclude("time.h"));

const TimeErrors = error{
    FailedToGetTime,
};

pub const Timestamp = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
};

pub fn Localtimestamp() !Timestamp {
        const ts = std.time.timestamp();
        var c_ts: c.time_t = @intCast(ts);

        const time_ptr = c.localtime(&c_ts);
        if (time_ptr == null)
            return TimeErrors.FailedToGetTime;

        const c_tm = time_ptr.?; // *c.struct_tm

        const tmval = c_tm.*; // now tmval is value of type c.struct_tm
 
        return Timestamp{
            .tm_sec = tmval.tm_sec,
            .tm_min = tmval.tm_min,
            .tm_hour = tmval.tm_hour,
            .tm_mday = tmval.tm_mday,
            .tm_mon = tmval.tm_mon,
            .tm_year = tmval.tm_year,
            .tm_wday = tmval.tm_wday,
            .tm_yday = tmval.tm_yday,
            .tm_isdst = tmval.tm_isdst,
        };
    }

