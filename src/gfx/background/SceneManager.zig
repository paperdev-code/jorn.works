scenes: std.ArrayList(Scene),
current_scene_idx: usize,

pub fn init(scene_storage: []Scene) SceneManager {
    return .{
        .scenes = .initBuffer(scene_storage),
        .current_scene_idx = 0,
    };
}

pub fn addScene(
    scene_manager: *SceneManager,
    comptime container: type,
    args: anytype,
) error{SceneSetupError}!void {
    if (std.meta.hasFn(container, "setup")) {
        @call(.auto, container.setup, args) catch {
            return error.SceneSetupError;
        };
    }
    const scene = scene_manager.scenes.addOneAssumeCapacity();
    scene.* = .{
        .step_fn = &container.step,
        .scene_transition_fn = if (std.meta.hasFn(container, "sceneTransition"))
            &container.sceneTransition
        else
            null,
    };
}

pub fn stepScene(scene_manager: *const SceneManager, context: *const Scene.Context) Scene.PostStepBehaviour {
    const scenes = scene_manager.scenes.items;
    if (scenes.len == 0) return .none;
    const scene_idx = scene_manager.current_scene_idx;
    return scenes[scene_idx].step_fn(context);
}

pub fn nextScene(scene_manager: *SceneManager, context: *const Scene.Context) void {
    const scenes = scene_manager.scenes.items;
    if (scenes.len == 0) return;
    const next_scene_idx = (scene_manager.current_scene_idx + 1) % scenes.len;
    scene_manager.current_scene_idx = next_scene_idx;
    (scenes[next_scene_idx].scene_transition_fn orelse return)(context);
}

const SceneManager = @This();
const Scene = @import("Scene.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");
