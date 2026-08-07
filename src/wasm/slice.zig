pub const Slice = packed struct(u64) {
    ptr: usize,
    len: usize,

    pub fn alloc(gpa: Allocator, len: usize) !Slice {
        const bytes = try gpa.allocSentinel(u8, len, 0);
        return .{
            .ptr = @intFromPtr(bytes.ptr),
            .len = len,
        };
    }

    pub fn free(slice: *const Slice, gpa: Allocator) void {
        gpa.free(slice.asBuffer());
    }

    pub fn asBuffer(slice: *const Slice) [:0]u8 {
        return @as([*:0]u8, @ptrFromInt(slice.ptr))[0..slice.len :0];
    }
};

const Allocator = std.mem.Allocator;
const std = @import("std");
