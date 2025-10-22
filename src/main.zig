const std = @import("std");
const network = @import("network");
const stdout_writer = std.io.getStdOut().writer();
const clocktime = @import("clocktime.zig");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpallocator = gpa.allocator();
const stdin = std.io.getStdIn();
const reader = stdin.reader();

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

fn connectSocket(
    writer: std.fs.File.Writer, 
    allocator: std.mem.Allocator, 
    port_number: u16
) !*SocketConn {
    const conn = try allocator.create(SocketConn);
    errdefer allocator.destroy(conn);

    conn.* = SocketConn{
        .sock = try network.Socket.create(allocator, .udp),
        .writer = writer,
        .allocator = allocator,
    };

    try conn.sock.bind(.{
        .address = try network.Address.resolveIp("0.0.0.0", port_number),
    });

    try writer.print("Connected to chatroom at port: {d}\n", .{port_number});
    return conn;
}

const SocketConn = struct {
    sock: network.Socket,
    writer: std.fs.File.Writer,
    allocator: std.mem.Allocator,

    pub fn send(this: *@This(), destination_ip: []const u8, port: u16, message: []const u8) !void {
        const destination = try network.Address.resolveIp(destination_ip, port);
        _ = try this.sock.sendTo(destination, message);
    }

    pub fn close(this: *@This()) void {
        this.sock.close();
        network.deinit();
    }

    pub fn receive(this: *@This(), writer: std.fs.File.Writer) !void {
        var buf: [1024]u8 = undefined;

        const result = try this.sock.receiveFrom(&buf);
        const data = buf[0..result.size];
        
        try writer.print("{s}\n", .{data});
    }
};


pub fn main() !void {
    try network.init();
    defer network.deinit();

    const args = std.process.argsAlloc(gpallocator) catch |err| {
        try stdout_writer.print("Could not retrieve arguments: {s}\n", .{@errorName(err)});
        return;
    };
    defer std.process.argsFree(gpallocator, args);

    if (args.len != 2) {
        try stdout_writer.print("Usage: {s} <port_number>\n", .{args[0]});
        return;
    }

    const port = try std.fmt.parseInt(u16, args[1], 10);

    try stdout_writer.print("Enter username: \n", .{});
    var buf: [100]u8 = undefined;

    const line = try reader.readUntilDelimiterOrEof(&buf, '\n');
    const username = if (line) |usrnme| usrnme else []const u8{"Anonymous"};


    const SocketConnection = try connectSocket(stdout_writer, gpallocator, port);
    defer SocketConnection.close();

    
    while (true) {
        try SocketConnection.receive(stdout_writer);

        try stdout_writer.print("[{s}]: ", .{username});
        const msgLine = try reader.readUntilDelimiterOrEof(&buf, '\n');

        if (msgLine) |writtenMsg| {
            const ourMsg = msg{ .data = writtenMsg, .userName = username };
            const text = try ourMsg.new(gpallocator);
            try SocketConnection.send("127.0.0.1", port, text);
            gpallocator.free(text);
        }
    }
}

