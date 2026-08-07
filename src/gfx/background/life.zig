const rulesets = [2][]const u1{
    &.{ 0, 0, 0, 1, 0 }, // birth
    &.{ 0, 0, 1, 1, 0 }, // survival
};

// const max_linger_time: f32 = 15.0;
const offsets = [_]i17{ -1, 0, 1 };

pub fn step(context: *const Scene.Context) Scene.PostStepBehaviour {
    const curr = context.curr;
    const prev = context.prev;
    const width, const height = curr.dimensions();
    for (0..height) |y| for (0..width) |x| {
        var neighbours: u8 = 0;
        inline for (offsets) |y_offset| inline for (offsets) |x_offset| {
            comptime if (y_offset == 0 and x_offset == 0) continue;
            neighbours += prev.bitget(
                @as(i17, @intCast(x)) + x_offset,
                @as(i17, @intCast(y)) + y_offset,
            );
        };
        const ruleset = rulesets[prev.bitget(@intCast(x), @intCast(y))];
        curr.bitset(
            @intCast(x),
            @intCast(y),
            .dot_set,
            ruleset[@min(neighbours, ruleset.len - 1)],
        );
    };
    // return if (context.time_total_secs < max_linger_time) .swap else .transition;
    return .swap;
}

const Scene = @import("Scene.zig");
const dots = @import("dots");
