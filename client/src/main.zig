const std = @import("std");
const net = std.net;
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const stream = try net.tcpConnectToHost(allocator, "127.0.0.1", 3000);
    defer stream.close();

    _ = try std.Thread.spawn(.{}, listenForResponse, .{stream.reader()});
    _ = try std.Thread.spawn(.{}, listenForUserInput, .{ stdin, stream.writer() });
    while (true) {}
}

fn listenForResponse(reader: std.net.Stream.Reader) !void {
    var buffer: [1024]u8 = undefined;
    while (true) {
        const bytes_read = try reader.read(&buffer);
        try stdout.print("{s}", .{buffer[0..bytes_read]});
    }
}

fn listenForUserInput(reader: std.fs.File.Reader, writer: std.net.Stream.Writer) !void {
    var buffer: [1024]u8 = undefined;
    var user_input: usize = 0;
    var bytes_written: usize = 0;
    while (true) {
        user_input = try reader.read(&buffer);
        bytes_written = try writer.write(buffer[0..user_input]);

        if (user_input <= 1 or bytes_written <= 1) {
            try stdout.print("Exiting!\n", .{});
            std.os.exit(0);
        }

        buffer = undefined;
    }
}
