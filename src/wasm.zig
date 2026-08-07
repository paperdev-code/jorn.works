pub const Slice = @import("wasm/slice.zig").Slice;
pub const gpa = std.heap.wasm_allocator;
pub const logFn = @import("wasm/log_fn.zig").logFn;
pub const panic = @import("wasm/panic.zig").panic;

const SetupResult = enum(u8) {
    success,
    failure,
    _,
};

export fn setup(config_zon: Slice) SetupResult {
    if (!std.meta.hasFn(root, "setup")) {
        @compileError("root.setup is inaccessible, or not a function.");
    }

    const setupFn = root.setup;
    const SetupFn = @TypeOf(setupFn);
    const setup_fn_info = @typeInfo(SetupFn).@"fn";

    if (setup_fn_info.is_generic) {
        @compileError("root.setup cannot be a generic function.");
    }

    const config_type: ?type = comptime if (setup_fn_info.param_types.len > 0)
        setup_fn_info.param_types[0].?
    else
        null;

    var config: ?(config_type orelse void) = null;

    if (config_type) |Config| {
        var diag: std.zon.parse.Diagnostics = .{};
        defer diag.deinit(gpa);

        config = std.zon.parse.fromSlice(
            Config,
            gpa,
            config_zon.asBuffer(),
            &diag,
            .{ .free_on_error = true },
        ) catch |err| switch (err) {
            error.ParseZon => {
                log.err("failed to parse config during setup: {f}", .{diag});
                return .failure;
            },
            error.OutOfMemory => @panic("OOM"),
        };
    }

    const result = @call(.auto, setupFn, if (config_type) |_| .{config.?} else .{});
    const Result = @TypeOf(result);
    const result_info = @typeInfo(Result);

    if (result_info == .void) return .succes;

    if (result_info == .error_union) {
        const error_set_info = @typeInfo(result_info.error_union.error_set).error_set;
        const error_names = error_set_info.error_names orelse .{};
        const may_return_oom = blk: {
            for (error_names) |error_name| if (std.mem.eql(u8, error_name, "OutOfMemory")) break :blk true;
            break :blk false;
        };
        const result_unwrapped = result catch |err| {
            if (may_return_oom and err == error.OutOfMemory) @panic("OOM");
            log.err("setup failed: {t}", .{err});
            return .failure;
        };
        if (result_unwrapped != {}) @compileError("root.setup may not return a value.");
    }

    return .success;
}

export fn alloc(len: usize) Slice {
    return Slice.alloc(gpa, len) catch @panic("OOM");
}

export fn free(slice: Slice) void {
    slice.free(gpa);
}

comptime {
    check_panic: {
        if (@hasDecl(root, "panic")) {
            if (root.panic == panic) break :check_panic;
        }
        @compileError("root.panic is not set correctly!");
    }

    check_logfn: {
        if (@hasDecl(root, "std_options")) {
            if (root.std_options.logFn == logFn) break :check_logfn;
        }
        @compileError("root.logFn is not set correctly!");
    }
}

const log = if (@hasDecl(root, "log")) root.log else std.log;
const root = @import("root");
const std = @import("std");
