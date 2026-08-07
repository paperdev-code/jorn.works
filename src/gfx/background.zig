pub const std_options: std.Options = .{ .logFn = wasm.logFn };
pub const panic = wasm.panic;
pub const log = std.log.scoped(.background);

const Config = struct {
    dots: struct { width: u16, height: u16 },
    boat_stl: u64,
    face_stl: u64,
};

var time_total_secs: f32 = 0.0;
var curr: *const dots.Context = undefined;
var prev: *const dots.Context = undefined;
var output: wasm.Slice = undefined;
var scene_storage: [4]Scene = undefined;
var scene_manager: SceneManager = undefined;

pub fn setup(config: Config) !void {
    inline for (.{ &curr, &prev }) |ctx_ptr| {
        const buffer: []u8 = try gpa.alloc(u8, dots.mem.calculateBufferSize(
            config.dots.width,
            config.dots.height,
        ));
        const context = try gpa.create(dots.Context);
        @memset(buffer, 0);
        context.* = dots.Context.init(
            buffer,
            config.dots.width,
            config.dots.height,
        ) catch unreachable;
        ctx_ptr.* = context;
    }

    output = try wasm.Slice.alloc(gpa, capacity: {
        const glyph_bytes = curr.buffer.len * "\u{2800}".len;
        const break_bytes = curr.rows * "\n".len;
        break :capacity break_bytes + glyph_bytes;
    });

    scene_manager = .init(&scene_storage);
    try scene_manager.addScene(@import("background/boat.zig"), .{
        gpa,
        @as(wasm.Slice, @bitCast(config.boat_stl)),
        @as(wasm.Slice, @bitCast(config.face_stl)),
    });
    try scene_manager.addScene(@import("background/life.zig"), .{});
    log.info("initialized.", .{});
}

export fn step(time_delta_secs: f32, mouse_pos_x: f32, mouse_pos_y: f32) void {
    const context: Scene.Context = .{
        .curr = curr,
        .prev = prev,
        .time_delta_secs = time_delta_secs,
        .time_total_secs = time_total_secs,
        .mouse_pos_x = mouse_pos_x,
        .mouse_pos_y = mouse_pos_y,
    };
    const post_step_behaviour = scene_manager.stepScene(&context);
    if (post_step_behaviour.isSwap()) {
        std.mem.swap(*const dots.Context, &prev, &curr);
    }
    if (post_step_behaviour.isTransition()) {
        scene_manager.nextScene(&context);
        time_total_secs = 0.0;
    } else {
        time_total_secs += time_delta_secs;
    }
}

export fn render() wasm.Slice {
    var reader: std.Io.Reader = .fixed(curr.buffer);
    var writer: std.Io.Writer = .fixed(output.asBuffer());
    var codec: dots.glyph.Codec = .{
        .reader = &reader,
        .writer = &writer,
    };
    var last_err: ?dots.glyph.Codec.Error = null;
    defer if (last_err) |err| {
        log.warn("could not render whole display: {t}", .{err});
    };
    for (0..curr.rows) |_| {
        codec.encode(curr.columns) catch |err| {
            last_err = err;
            break;
        };
        writer.writeAll("\n") catch |err| {
            last_err = err;
            break;
        };
    }
    return output;
}

const Scene = @import("background/Scene.zig");
const SceneManager = @import("background/SceneManager.zig");
const dots = @import("dots");
const std = @import("std");
const gpa = wasm.gpa;
const wasm = @import("wasm");
