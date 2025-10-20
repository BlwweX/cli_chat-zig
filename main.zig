const std = @import("std");
const network = @import("network");
const stdout = std.io.getStdOut().writer();
const clocktime = @import("clocktime.zig");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpallocator = gpa.allocator();

const msg = struct {
    const self = @This();
    data: []const u8,
    userName: []const u8,
    sendTime: clocktime.Timestamp = undefined,
    
    pub fn new(this: *self, allocator: std.mem.Allocator) ![]u8 {
        const ourSendTime: clocktime.Timestamp = clocktime.Localtimestamp() catch |err| return err;
        this.sendTime = ourSendTime;

        return try std.fmt.allocPrint(allocator, "[{d}:{d}:{d}] {s}: {s}\n", .{ourSendTime.tm_hour, ourSendTime.tm_min, ourSendTime.tm_sec, this.userName, this.data});
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
    var myMsg = msg{.userName = "exx", .data = "foobar"};
    _ = &myMsg;

    stdout.print("{s}\n", .{try myMsg.new(gpallocator)}) catch |err| return err;
}
