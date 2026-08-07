pub const PostStepBehaviour = enum {
    none,
    swap,
    transition,
    transition_swap,

    pub fn isTransition(post_step_behaviour: PostStepBehaviour) bool {
        return switch (post_step_behaviour) {
            .transition, .transition_swap => true,
            else => false,
        };
    }

    pub fn isSwap(post_step_behaviour: PostStepBehaviour) bool {
        return switch (post_step_behaviour) {
            .swap, .transition_swap => true,
            else => false,
        };
    }
};

pub const Context = struct {
    prev: *const dots.Context,
    curr: *const dots.Context,
    time_delta_secs: f32,
    time_total_secs: f32,
    mouse_pos_x: f32,
    mouse_pos_y: f32,
};

scene_transition_fn: ?*const fn (context: *const Context) void,
step_fn: *const fn (context: *const Context) PostStepBehaviour,

const dots = @import("dots");
