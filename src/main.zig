const std = @import("std");
const clocktime = @import("clocktime.zig");
const net = std.net;
const posix = std.posix;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const gpallocator = gpa.allocator();

const stdin = std.io.getStdIn();
const reader = stdin.reader();
const stdout_writer = std.io.getStdOut().writer();

fn formatChat(allocator: std.mem.Allocator, buf: []const u8, username: []const u8) ![]u8 {
    const ourSendTime: clocktime.Timestamp = clocktime.Localtimestamp() catch |err| return err;

    return try std.fmt.allocPrint(allocator, "[{d}:{d}:{d}] {s}: {s}\n",
        .{ ourSendTime.tm_hour, ourSendTime.tm_min, ourSendTime.tm_sec, username, buf });
}

fn readLine() ![]u8 {
    var buf: [256]u8 = undefined;
    const stdin_reader = std.io.getStdIn().reader();
    const line_opt = try stdin_reader.readUntilDelimiterOrEof(&buf, '\n');
    if (line_opt) |line| {
        const trimmed = std.mem.trimRight(u8, line, "\r\n");
        return try std.heap.page_allocator.dupe(u8, trimmed);
    } else {
        return error.EndOfStream;
    }
}

fn createListener(port_number: u16, writer: std.fs.File.Writer) !MessageSocket {
    const address = try std.net.Address.parseIp("127.0.0.1", port_number);

    const tpe: u32 = posix.SOCK.STREAM;
    const protocol: comptime_int = posix.IPPROTO.TCP;
    const listener = try posix.socket(address.any.family, tpe, protocol);
    
    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, 128);

    return MessageSocket{
        .listener = listener,
        .writer = writer,
        .port_num = port_number,
    };
}

const MessageSocket = struct {
    listener: std.posix.socket_t,
    writer: std.fs.File.Writer,
    port_num: u16,
    
    
    
    pub fn readFromPort(self: @This()) !void {
        while (true) {
            var client_addr: net.Address = undefined;
            var client_addr_len: posix.socklen_t = @sizeOf(net.Address);
            const socket = try posix.accept(self.listener, &client_addr.any, &client_addr_len, 0);

            var buf: [64]u8 = undefined;
            const n = posix.read(socket, &buf) catch {
                _ = posix.close(socket);
                continue;
            };

            const username = std.mem.trimRight(u8, buf[0..n], "\r\n");
            const name_copy = gpallocator.dupe(u8, username) catch {
                _ = posix.close(socket);
                continue;
            };

            client_lock.lock();
            _ = clients.append(.{ .socket = socket, .username = name_copy }) catch {};
            client_lock.unlock();

            const join_msg = std.fmt.allocPrint(gpallocator, "{s} joined the chat\n", .{username}) catch "";
            broadcast(socket, join_msg);
            gpallocator.free(join_msg);

            _ = std.Thread.spawn(.{}, handleClient, .{socket}) catch {};
        }
    }



    pub fn writeToPort(self: @This(), socket: posix.socket_t, writeMsg: []const u8) !void {
        _ = &self;
        var pos: usize = 0;

        while (pos < writeMsg.len) {
            const written = try posix.write(socket, writeMsg[pos..]);
            if (written == 0) {
                return error.Closed;
            }
            pos += written;
        }
    }
};

const Client = struct {
    socket: posix.socket_t,
    username: []const u8,
};

var clients = std.ArrayList(Client).init(gpallocator);
var client_lock: std.Thread.Mutex = .{};

fn listenLoop(conn: *const MessageSocket) void {
    while (true) {
        _ = conn.readFromPort() catch {};
    }
}


fn handleClient(socket: posix.socket_t) void {
    var buf: [512]u8 = undefined;
    while (true) {
        const n = posix.read(socket, &buf) catch break;
        if (n == 0) break;
        
        const sender_name = getUsername(socket);
        const formatted = std.fmt.allocPrint(gpallocator, "{s}: {s}", .{sender_name, buf[0..n]}) catch "";
        broadcast(socket, formatted);
        gpallocator.free(formatted);
    }

    client_lock.lock();
    defer client_lock.unlock();

    var i: usize = 0;
    while (i < clients.items.len) : (i += 1) {
        if (clients.items[i].socket == socket) {
            const name_to_free = clients.items[i].username;

            _ = clients.swapRemove(i);
            gpallocator.free(name_to_free);
            break;
        }
    }

    _ = posix.close(socket);
}

fn getUsername(socket: posix.socket_t) []const u8 {
    client_lock.lock();
    defer client_lock.unlock();

    for (clients.items) |client| {
        if (client.socket == socket) return client.username;
    }
    return "Unknown";
}


fn broadcast(sender: posix.socket_t, msg: []const u8) void {
    client_lock.lock();
    defer client_lock.unlock();

    for (clients.items) |client| {
        if (client.socket != sender) {
            _ = posix.write(client.socket, msg) catch {};
        }
    }
}

fn readAndSendChat(username: []const u8, tcpconn: MessageSocket, socket: posix.socket_t) !void {
    const currentChat = try readLine();
    const formatted = try formatChat(gpallocator, currentChat, username);
    try stdout_writer.print("{s}\n", .{formatted});

    defer gpallocator.free(formatted);
    try tcpconn.writeToPort(socket, formatted);
}

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
    const tcpconn: MessageSocket = try createListener(port, stdout_writer);

    try stdout_writer.print("Server listening on port {d}\n", .{port});

    try tcpconn.readFromPort();
}
