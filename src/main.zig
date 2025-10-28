const std = @import("std");
const clocktime = @import("clocktime.zig");
const net = std.net;
const posix = std.posix;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpallocator = gpa.allocator();

const stdin = std.io.getStdIn();
const reader = stdin.reader();
const stdout_writer = std.io.getStdOut().writer();

const msg = struct {
    const self = @This();
    data: []const u8,
    userName: []const u8,
    sendTime: clocktime.Timestamp = undefined,
    
    pub fn new(this: *self, allocator: std.mem.Allocator) ![]u8 {
        const ourSendTime: clocktime.Timestamp = clocktime.Localtimestamp() catch |err| return err;
        this.sendTime = ourSendTime;
        return try std.fmt.allocPrint(allocator, "[{d}:{d}:{d}] {s}: {s}\n",
            .{ ourSendTime.tm_hour, ourSendTime.tm_min, ourSendTime.tm_sec, this.userName, this.data });
    }
};

fn readLine() ![]const u8 {
    const stdin_reader = std.io.getStdIn().reader();
    var result: [256]u8 = undefined;
    const slice = try stdin_reader.readUntilDelimiter(&result, '\n');
    const clean = std.mem.trimRight(u8, slice, "\r\n");
    return clean;
}

fn createListener(
port_number: u16, 
writer: std.fs.File.Writer
) !MessageSocket {
    const address = try std.net.Address.parseIp("127.0.0.1", port_number);

    const tpe: u32 = posix.SOCK.STREAM;
    const protocol: comptime_int = posix.IPPROTO.TCP;
    const listener = try posix.socket(address.any.family, tpe, protocol);
    
    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

    try posix.bind(listener, &address.any, address.getOsSockLen());

    return MessageSocket{
        .listener = listener,
        .writer = writer,
        .port_num = port_number
    };
}

pub const MessageSocket = struct {
    listener: std.posix.socket_t,
    writer: std.fs.File.Writer,
    port_num: u16,
    
    pub fn read(self: @This()) !posix.socket_t {
        var client_addr: net.Address = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(net.Address);

        const socket = try posix.accept(self.listener,  &client_addr.any, &client_addr_len, 0);

       var buf: [128]u8 = undefined;

        const readBytes = try posix.read(socket, &buf);
        

        if (readBytes != 0) {
            try self.writer.print("{s}\n", .{buf[0..readBytes]});
        }

        return socket;
    }

    pub fn write(socket: posix.socket_t, writeMsg: []const u8) !void {
        var pos: usize = 0;

        while (pos < msg.len) {
            const written = try posix.write(socket, writeMsg[pos..]);
            if (written == 0) {
                return error.Closed;
            }
            pos += written;
        }
    }
       
};

pub fn main() !void {
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
    const username = if (line) |usrnme| usrnme else "Anonymous"; 

    const tcpconn: MessageSocket = createListener(port, stdout_writer) catch |err| {
        std.debug.print("{s}\n", .{@errorName(err)});
        return err;
    }; 

    const socket = try tcpconn.read();

    while (true) {
        var listenThread = try std.Thread.spawn(.{}, tcpconn.read, .{&tcpconn});
        listenThread.join();
    }

    while (true) {
        const inputLine: [128]u8 = undefined;

        const n = try std.io.Reader.readUntilDelimiterOrEof(&line, '\n');
        _  = &n;


        if (line.len > 0) {
            stdout_writer.print("{s}\n", .{inputLine});
            
            const createdMsg = msg{.data = inputLine, .userName = username};
            try tcpconn.write(socket, createdMsg.new(gpallocator));
        }
    }

}
