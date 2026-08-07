const help_fmt =
    \\- {[name]s}
    \\usage:
    \\  {[exe_path]s} --host <ip>:<port> --root <directory>
    \\
;

fn helpArgs(exe_path: [:0]const u8) struct { name: []const u8, exe_path: [:0]const u8 } {
    return .{
        .name = std.fs.path.stem(@src().file),
        .exe_path = exe_path,
    };
}

fn printHelpAndExitFail(stderr: *std.Io.Writer, help_args: anytype) noreturn {
    stderr.print(help_fmt, help_args) catch {};
    stderr.flush() catch {};
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    var stderr_buffer: [0xffa]u8 = @splat(0);
    var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    var args = try init.minimal.args.iterateAllocator(init.arena.allocator());
    const help_args = helpArgs(args.next().?);

    var addr: ?std.Io.net.IpAddress = null;
    var root: ?std.Io.Dir = null;
    const io = init.io;

    while (args.next()) |arg| switch (std.meta.stringToEnum(enum {
        @"-h",
        @"--help",
        @"--host",
        @"--root",
    }, arg) orelse {
        log.err("unknown option, '{s}'", .{arg});
        printHelpAndExitFail(stderr, help_args);
    }) {
        .@"-h", .@"--help" => {
            stderr.print(help_fmt, help_args) catch {};
            stderr.flush() catch {};
            std.process.cleanExit(io);
            return;
        },
        .@"--host" => {
            const host = args.next() orelse {
                log.err("expected --host value", .{});
                printHelpAndExitFail(stderr, help_args);
            };
            addr = std.Io.net.IpAddress.parseLiteral(host[0.. :0]) catch |err| {
                log.err("failed to parse --host: {t}", .{err});
                std.process.exit(1);
            };
        },
        .@"--root" => {
            const root_path = args.next() orelse {
                log.err("expected --root value", .{});
                printHelpAndExitFail(stderr, help_args);
            };
            root = std.Io.Dir.cwd().openDir(io, root_path, .{
                .access_sub_paths = true,
                .follow_symlinks = false,
                .iterate = false,
            }) catch |err| {
                log.err("failed to open --root directory: {t}", .{err});
                std.process.exit(1);
            };
        },
    };

    if (addr == null) {
        log.err("missing required parameter, --host", .{});
        printHelpAndExitFail(stderr, help_args);
    }

    if (root == null) {
        log.err("missing required parameter, --root", .{});
        printHelpAndExitFail(stderr, help_args);
    }

    var tcp_server = try addr.?.listen(io, .{
        .protocol = .tcp,
        .reuse_address = true,
    });

    defer tcp_server.deinit(io);
    log.info("accepting connections @ http://{f}", .{addr.?});

    accept: while (true) _ = try io.concurrent(onTcpAccept, .{
        io,
        init.gpa,
        &root.?,
        tcp_server.accept(io) catch |err| {
            log.warn("failed to accept connection: {t}", .{err});
            continue :accept;
        },
    });
}

fn respondEmpty(request: *std.http.Server.Request, status: std.http.Status) void {
    request.respond("", .{ .keep_alive = false, .status = status }) catch {};
}

fn onTcpAccept(io: std.Io, gpa: std.mem.Allocator, root: *std.Io.Dir, stream: std.Io.net.Stream) void {
    const stream_mut: *std.Io.net.Stream = @constCast(&stream);
    defer stream_mut.close(io);

    var stream_reader_buffer: [0xffa]u8 = @splat(0);
    var stream_reader = stream_mut.reader(io, &stream_reader_buffer);
    var stream_writer = stream_mut.writer(io, &.{});

    var http: std.http.Server = .init(
        &stream_reader.interface,
        &stream_writer.interface,
    );

    var request = http.receiveHead() catch |err| {
        if (err == error.HttpConnectionClosing) {
            log.debug("connection closed", .{});
            return;
        }
        log.warn("failed to recieve head: {t}", .{err});
        return;
    };

    if (request.head.method != .GET) {
        respondEmpty(&request, .method_not_allowed);
        return;
    }

    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);

    var path: []const u8 = std.fs.path.resolve(fba.allocator(), &.{request.head.target}) catch |err| {
        log.warn("failed to resolve target, target={s}: {t}", .{ request.head.target, err });
        respondEmpty(&request, .internal_server_error);
        return;
    };

    path = if (std.mem.eql(u8, path, "/")) "/index.html" else path;
    std.debug.assert(path[0] == '/');

    const content_type = std.StaticStringMap([]const u8).initComptime(&.{
        .{ ".html", "text/html" },
        .{ ".css", "text/css" },
        .{ ".js", "text/javascript" },
        .{ ".wasm", "application/wasm" },
        .{ ".stl", "model/stl" },
    }).get(std.fs.path.extension(path)) orelse "application/octet-stream";

    var file = root.openFile(io, path[1..], .{
        .mode = .read_only,
        .lock = .shared,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            respondEmpty(&request, .not_found);
            return;
        },
        else => {
            log.warn("failed to open file: {t}", .{err});
            respondEmpty(&request, .internal_server_error);
            return;
        },
    };
    defer file.close(io);

    var file_reader = file.reader(io, &buffer);
    var file_content: std.ArrayList(u8) = .empty;
    defer file_content.deinit(gpa);

    file_reader.interface.appendRemaining(gpa, &file_content, .unlimited) catch @panic("OOM");
    request.respond(file_content.items, .{
        .keep_alive = false,
        .extra_headers = &.{.{ .name = "Content-Type", .value = content_type }},
    }) catch {};

    log.debug("target={s}", .{path});
}

const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.http_server);
