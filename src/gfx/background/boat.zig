const Vec3d = struct {
    x: f32,
    y: f32,
    z: f32,

    pub const zeroes = Vec3d{ .x = 0.0, .y = 0.0, .z = 0.0 };

    pub fn all(v: f32) Vec3d {
        return .{ .x = v, .y = v, .z = v };
    }

    pub fn fromVector(v: @Vector(3, f32)) Vec3d {
        return .{ .x = v[0], .y = v[1], .z = v[2] };
    }

    pub fn rotate(vec3d: *Vec3d, radians: Vec3d) void {
        const x_sin = @sin(radians.x);
        const x_cos = @cos(radians.x);
        const y_sin = @sin(radians.y);
        const y_cos = @cos(radians.y);
        const z_sin = @sin(radians.z);
        const z_cos = @cos(radians.z);

        var tmp: Vec3d = vec3d.*;

        // x-axis
        tmp.y = vec3d.y * x_cos - vec3d.z * x_sin;
        tmp.z = vec3d.y * x_sin + vec3d.z * x_cos;
        vec3d.y = tmp.y;
        vec3d.z = tmp.z;

        // y-axis
        tmp.x = vec3d.x * y_cos + vec3d.z * y_sin;
        tmp.z = -vec3d.x * y_sin + vec3d.z * y_cos;
        vec3d.x = tmp.x;
        vec3d.z = tmp.z;

        // z-axis
        tmp.x = vec3d.x * z_cos - vec3d.y * z_sin;
        tmp.y = vec3d.x * z_sin + vec3d.y * z_cos;
        vec3d.x = tmp.x;
        vec3d.y = tmp.y;
    }

    pub fn scale(vec3d: *Vec3d, scalar: f32) void {
        vec3d.x *= scalar;
        vec3d.y *= scalar;
        vec3d.z *= scalar;
    }

    pub fn translate(vec3d: *Vec3d, translation: Vec3d) void {
        vec3d.x += translation.x;
        vec3d.y += translation.y;
        vec3d.z += translation.z;
    }

    pub fn asVector(vec3d: Vec3d) @Vector(3, f32) {
        return .{ vec3d.x, vec3d.y, vec3d.z };
    }

    pub fn rotationForFacingPointOnViewport(vec3d: *Vec3d, x: f32, y: f32) Vec3d {
        const direction = @Vector(3, f32){ x, y, 0.0 } - vec3d.asVector();
        const magnitude: f32 = @sqrt(@reduce(.Add, direction * direction));
        const normalized = direction / @as(@Vector(3, f32), @splat(magnitude + std.math.floatEps(f32)));
        const pitch: f32 = std.math.asin(normalized[1]);
        const yaw: f32 = -std.math.asin(normalized[0]);
        // log.debug("pitch={d}\nyaw={d}\n", .{ pitch, yaw });
        return .{ .x = pitch, .y = yaw, .z = 0.0 };
    }

    pub fn project(vec3d: *const Vec3d) struct { f32, f32 } {
        return .{
            vec3d.x / (vec3d.z + std.math.floatEps(f32)),
            vec3d.y / (vec3d.z + std.math.floatEps(f32)),
        };
    }

    pub fn format(vec3d: *const Vec3d, writer: *std.Io.Writer) !void {
        try writer.print("{{.x = {d}, .y = {d}, .z = {d}}}", .{ vec3d.x, vec3d.y, vec3d.z });
    }
};

const Triangle = struct {
    normal: Vec3d,
    vertices: [3]Vec3d,
};

const Model = struct {
    triangles: []Triangle,
    rotation: Vec3d,
    position: Vec3d,
    scale: f32,
    projection: []f32,

    const StlParserState = enum {
        solid,
        facet,
        normal,
        outer_loop,
        vertex_or_endloop,
        vertex,
        endloop,
        endfacet,
        endsolid_or_facet,
    };

    fn readKeyword(token: ?[]const u8, keyword: []const u8) !void {
        if (!std.mem.eql(u8, keyword, token orelse return error.UnexpectedEof)) {
            return error.ExpectedKeyword;
        }
    }

    fn readFloat(token: ?[]const u8) !f32 {
        return try std.fmt.parseFloat(f32, token orelse return error.UnexpectedEof);
    }

    fn readVec3d(it: *std.mem.TokenIterator(u8, .any)) !Vec3d {
        return .{
            .x = try readFloat(it.next()),
            .y = try readFloat(it.next()),
            .z = try readFloat(it.next()),
        };
    }

    pub fn fromStl(gpa: Allocator, ascii: [:0]const u8) !Model {
        var triangles: std.ArrayList(Triangle) = .empty;
        defer triangles.deinit(gpa);

        var triangle: Triangle = undefined;
        var vert_idx: usize = 0;

        var it = std.mem.tokenizeAny(u8, ascii[0..ascii.len], " \r\n");
        parse: switch (StlParserState.solid) {
            .solid => {
                try readKeyword(it.next(), "solid");
                continue :parse .endsolid_or_facet;
            },
            .facet => {
                try readKeyword(it.next(), "facet");
                continue :parse .normal;
            },
            .normal => {
                try readKeyword(it.next(), "normal");
                triangle.normal = try readVec3d(&it);
                continue :parse .outer_loop;
            },
            .outer_loop => {
                try readKeyword(it.next(), "outer");
                try readKeyword(it.next(), "loop");
                continue :parse .vertex;
            },
            .vertex_or_endloop => {
                if (vert_idx < 3) {
                    continue :parse .vertex;
                }
                vert_idx = 0;
                continue :parse .endloop;
            },
            .vertex => {
                try readKeyword(it.next(), "vertex");
                triangle.vertices[vert_idx] = try readVec3d(&it);
                vert_idx += 1;
                continue :parse .vertex_or_endloop;
            },
            .endloop => {
                try readKeyword(it.next(), "endloop");
                continue :parse .endfacet;
            },
            .endfacet => {
                try readKeyword(it.next(), "endfacet");
                try triangles.append(gpa, triangle);
                continue :parse .endsolid_or_facet;
            },
            .endsolid_or_facet => {
                readKeyword(it.peek(), "endsolid") catch |err| switch (err) {
                    error.UnexpectedEof => return err,
                    error.ExpectedKeyword => continue :parse .facet,
                };
            },
        }

        const projection = try gpa.alloc(f32, triangles.items.len * 9);
        return .{
            .triangles = try triangles.toOwnedSlice(gpa),
            .rotation = .zeroes,
            .position = .zeroes,
            .scale = 1.0,
            .projection = projection,
        };
    }

    pub fn project(model: *const Model) []f32 {
        var projection: std.ArrayList(f32) = .initBuffer(model.projection);
        for (model.triangles) |original| {
            var transformed: Triangle = original;
            transformed.normal.rotate(model.rotation);
            if (transformed.normal.z >= -0.2) {
                continue;
            }
            inline for (0..original.vertices.len) |idx| {
                const vertex = &transformed.vertices[idx];
                vertex.rotate(model.rotation);
                vertex.scale(model.scale);
                vertex.translate(model.position);
            }
            const projected = .{
                transformed.vertices[0].project(),
                transformed.vertices[1].project(),
                transformed.vertices[2].project(),
            };
            inline for (0..projected.len) |idx| {
                projection.appendSliceAssumeCapacity(&projected[idx]);
            }
        }
        return projection.items;
    }
};

const boat_lives_max = 3;
const boat_position: Vec3d = .{ .x = 0.3, .y = 0.0, .z = 1.0 };
const boat_scale = 0.5;
var boat_state: BoatState = .{ .pop_in = .{} };
var boat_model: Model = undefined;
var face_model: Model = undefined;
var boat_target: Vec3d = .zeroes;
var boat_lives: u8 = boat_lives_max;

const PopInState = struct {
    const spawn_speed_secs: f32 = 3.0;

    time_since_spawn: f32 = 0.0,

    pub fn step(s: *PopInState, ctx: *const Scene.Context) void {
        s.time_since_spawn += ctx.time_delta_secs;
        const progress = s.time_since_spawn / spawn_speed_secs;
        if (progress >= 1.0) {
            boat_model.rotation.y = 0.0;
            boat_target = boat_model.rotation;
            boat_state.trigger(.follow);
        } else {
            boat_model.scale = boat_scale * easeOutCubic(progress);
            boat_target.y = easeOutCubic(progress) * std.math.tau * 8;
        }
    }
};

const FollowState = struct {
    const max_dizziness = 10;
    const dizziness_decrease_time = 2.0;
    dizziness: u8 = 0,
    dizziness_decrease: f32 = dizziness_decrease_time,

    pub fn step(s: *FollowState, ctx: *const Scene.Context) void {
        boat_target = boat_model.position.rotationForFacingPointOnViewport(
            ctx.mouse_pos_x,
            ctx.mouse_pos_y,
        );
        s.dizziness_decrease -= ctx.time_delta_secs;
        if (s.dizziness_decrease < 0.0) {
            s.dizziness -|= 1;
            s.dizziness_decrease = dizziness_decrease_time;
        }
        if (s.dizziness > max_dizziness) {
            boat_state.trigger(.dizzy);
        }
        const speed = @reduce(
            .Add,
            // it's easier to travel the Y axis, so we increase the influence of the X axis according to the aspect ratio,
            // Z axis is irrelevant
            (boat_model.rotation.asVector() - boat_target.asVector()) * @Vector(3, f32){
                ctx.curr.aspect,
                1.0,
                0.0,
            },
        );
        if (speed > 0.4) {
            s.dizziness += 1;
            s.dizziness_decrease = dizziness_decrease_time;
        }
    }
};

const DizzyState = struct {
    const dizzy_duration_secs: f32 = 5.0;
    const dizzy_wander_intensity: f32 = 0.6;

    time_since_dizzy: f32 = 0.0,

    pub fn step(s: *DizzyState, ctx: *const Scene.Context) void {
        s.time_since_dizzy += ctx.time_delta_secs;

        boat_target.x = dizzy_wander_intensity *
            ctx.curr.aspect *
            std.math.sin(ctx.time_total_secs * -std.math.pi);

        boat_target.y = dizzy_wander_intensity *
            std.math.cos(ctx.time_total_secs * -std.math.pi);

        if (s.time_since_dizzy > dizzy_duration_secs) {
            boat_state.trigger(.follow);
            boat_lives -|= 1;
        }
    }
};

const BoatStates = enum { pop_in, follow, dizzy };

const BoatState = union(BoatStates) {
    pop_in: PopInState,
    follow: FollowState,
    dizzy: DizzyState,

    pub fn trigger(state: *BoatState, comptime next_state: BoatStates) void {
        state.* = @unionInit(BoatState, @tagName(next_state), .{});
    }

    pub fn step(state: *BoatState, ctx: *const Scene.Context) void {
        switch (state.*) {
            .pop_in => state.pop_in.step(ctx),
            .follow => state.follow.step(ctx),
            .dizzy => state.dizzy.step(ctx),
        }
    }
};

pub fn setup(gpa: Allocator, boat_stl: wasm.Slice, face_stl: wasm.Slice) !void {
    boat_model = Model.fromStl(gpa, boat_stl.asBuffer()) catch |err| {
        log.err("failed to load boat from STL: {t}", .{err});
        return err;
    };
    face_model = Model.fromStl(gpa, face_stl.asBuffer()) catch |err| {
        log.err("failed to load face from STL: {t}", .{err});
        return err;
    };
    boat_model.position = boat_position;
    boat_model.scale = boat_scale;
    face_model.position = boat_position;
    face_model.scale = boat_scale;
}

pub fn step(context: *const Scene.Context) Scene.PostStepBehaviour {
    boat_state.step(context);
    if (boat_lives == 0) return .transition;

    var boat_delta: Vec3d = .fromVector(boat_target.asVector() - boat_model.rotation.asVector());
    boat_delta.scale(0.2);
    boat_model.rotation.translate(boat_delta);

    @memset(context.curr.buffer, 0);
    if (boat_state != .pop_in) {
        face_model.scale = boat_model.scale;
        face_model.rotation = boat_model.rotation;
        if (boat_state == .dizzy) {
            face_model.rotation.y += std.math.pi;
            face_model.rotation.x *= -1;
        }
        context.curr.triangles(face_model.project(), .dot_set, 1);
    }
    context.curr.triangles(boat_model.project(), .dot_set, 1);
    return .swap;
}

pub fn sceneTransition(_: *const Scene.Context) void {
    boat_lives = 1;
}

fn easeOutCubic(x: f32) f32 {
    return @min(1.0, 1 - std.math.pow(f32, 1 - x, 3));
}

const dots = @import("dots");
const Allocator = std.mem.Allocator;
const Reader = std.Io.Reader;
const Scene = @import("Scene.zig");
const log = std.log.scoped(.boat_scene);
const std = @import("std");
const wasm = @import("wasm");
