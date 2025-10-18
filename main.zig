const std = @import("std");
const network = @import("network");
const stdout = std.io.getStdOut().writer();
const c = @cImport(@cInclude("time.h"));

const timeStamp = struct {
    hour: u64,
    min: u64,
    sec: u64
};

const msg = struct {
    const self = @This();
    data: [256]u8,
    userName: []u8,
    sendTime: timeStamp,
    
    pub fn send(this: self, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "[{d}:{d}:{d}] {s}: {s}\n", .{this.sendTime.hour, this.sendTime.min, this.sendTime.sec, this.userName, this.data});
    }
};

fn readLine() ![]const u8 {
    const stdin_reader = std.io.getStdIn().reader();
    var result: [256]u8 = undefined;

    const slice = try stdin_reader.readUntilDelimiter(&result, '\n');
    const clean = std.mem.trimRight(u8, slice, "\r\n");

    return clean;
}



pub fn main() !void {
    stdout.print("{d}\n", .{std.time.timestamp()}) catch |err| {
        return err;
    };
}
