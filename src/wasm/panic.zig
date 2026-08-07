pub const panic = std.debug.FullPanic(panicFn);

fn panicFn(msg: []const u8, ret_addr: ?usize) noreturn {
    @branchHint(.cold);
    if (ret_addr) |addr|
        std.log.err("panic @ 0x{x}: {s}", .{ addr, msg })
    else
        std.log.err("panic: {s}", .{msg});
    @trap();
}

const std = @import("std");
