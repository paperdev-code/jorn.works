pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    var buffer: [0xffa]u8 = undefined;
    const scope_text = if (scope == .default) "" else "(" ++ @tagName(scope) ++ "): ";
    const message: []const u8 = std.fmt.bufPrint(
        &buffer,
        scope_text ++ format,
        args,
    ) catch blk: {
        const trunc: []const u8 = "<truncated>";
        std.mem.copyForwards(u8, buffer[buffer.len - trunc.len ..], trunc);
        break :blk &buffer;
    };
    console(@backingInt(level), message.ptr, message.len);
}

extern fn console(level: u8, ptr: [*]const u8, len: usize) void;

const std = @import("std");
