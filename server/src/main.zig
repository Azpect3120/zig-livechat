const std = @import("std");
const net = std.net;
const stdout = std.io.getStdOut().writer();

// Define server address
const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 3000);

pub fn main() !void {
    // Define server options
    const options = net.StreamServer.Options{
        .reuse_port = true,
        .reuse_address = true,
    };
    // Create server
    var server = net.StreamServer.init(options);
    defer {
        server.close();
        server.deinit();
    }

    // Init allocator and connections map
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var connections = std.StringHashMap(net.StreamServer.Connection).init(allocator);

    // Open server
    try server.listen(addr);
    try stdout.print("[INFO] Server listening at: {}\n", .{addr});

    // Accept connections
    while (true) {
        const client = try server.accept();
        _ = try std.Thread.spawn(.{}, handleConnection, .{ allocator, client, &connections });
    }
}

/// Handles client connections
fn handleConnection(allocator: std.mem.Allocator, client: net.StreamServer.Connection, connections: *std.hash_map.HashMap([]const u8, net.StreamServer.Connection, std.hash_map.StringContext, 80)) !void {
    var bytes_read: usize = 0;
    var bytes_written: usize = 0;

    // Connection successful
    bytes_written = try client.stream.write("Welcome to the server!\nSend a message: ");
    try stdout.print("[CONNECT] Client {any} has connected.\n", .{client.address});

    // Send message to all connected clients
    const user_connected_message = try std.fmt.allocPrint(allocator, "\n[SERVER] {any} Has connected\nSend a message: ", .{client.address});
    try broadcast(connections, client, user_connected_message);

    // Add client to connections map
    const client_address: []const u8 = try std.fmt.allocPrint(allocator, "{any}", .{client.address});
    try connections.*.put(client_address, client);

    // User failed to connect
    if (bytes_written == 0) {
        try stdout.print("[ERROR] Failed to send welcome message to client {any}\n", .{client.address});
        try stdout.print("[DISCONNECT] Client {any} has disconnected.\n", .{client.address});

        const user_failed_connection_message = try std.fmt.allocPrint(allocator, "\n[SERVER] {any} Failed to connect\nSend a message: ", .{client.address});
        try broadcast(connections, client, user_failed_connection_message);

        client.stream.close();
        return;
    }

    var buffer: [1024]u8 = undefined;
    while (true) {
        bytes_read = client.stream.read(&buffer) catch |err| {
            try stdout.print("[ERROR] Failed to read from client {any}: {any}\n", .{ client.address, err });
            break;
        };

        // Broadcast message to all connected clients
        if (bytes_read > 0) {
            try stdout.print("[MESSAGE] Received {d} bytes from {any}\n", .{ bytes_read, client.address });

            const message = try std.fmt.allocPrint(allocator, "\n{any} says: {s}Send a message: ", .{ client.address, buffer[0..bytes_read] });
            try broadcast(connections, client, message);
        } else break;

        buffer = undefined;
        bytes_written = 0;
        bytes_read = 0;
    }

    // User has disconnected
    const message = try std.fmt.allocPrint(allocator, "\n[SERVER] {any} Has disconnected\nSend a message: ", .{client.address});
    try broadcast(connections, client, message);
    try stdout.print("[DISCONNECT] Client {any} has disconnected.\n", .{client.address});

    // Remove client from connections map
    const removed = connections.*.remove(client_address);
    if (!removed) try stdout.print("[ERROR] Failed to remove client {any} from the connections map\n", .{client.address});

    // Close client connection
    client.stream.close();
}

/// Broadcasts a message to all connected clients EXCEPT the client who sent the message
fn broadcast(connections: *std.hash_map.HashMap([]const u8, net.StreamServer.Connection, std.hash_map.StringContext, 80), client: net.StreamServer.Connection, message: []const u8) !void {
    var itter = connections.*.iterator();
    while (itter.next()) |val| {
        const reciever = val.value_ptr.*;

        // If the client is the receiver
        if (std.net.Address.eql(reciever.address, client.address)) {
            _ = try client.stream.write("Send a message: ");
            continue;
        }

        var bytes_written: usize = 0;
        bytes_written = try reciever.stream.write(message);

        // Log message sent in server logs
        try stdout.print("[MESSAGE] Sent {d} bytes to the {any}\n", .{ bytes_written, reciever.address });
    }
}
