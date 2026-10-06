const std = @import("std");
const os_api = @import("os_api.zig");

pub const ErrorCategory = enum(u32) {
    none = 0,
    access_denied = 1,
    invalid_process = 2,
    invalid_argument = 3,
    resource_exhausted = 4,
    unsupported = 5,
    system = 6,
};

pub const ProcessError = struct {
    category: ErrorCategory,
    native_code: u32,
};

pub const Observation = union(enum) {
    exited: u32,
    signaled: u32,
    stopped: u32,
};

pub const TerminationAction = union(enum) {
    signal: u32,
    exit_code: u32,
};

pub const ProcessOutcome = union(enum) {
    clean_stop,
    intentional_termination,
    crash_exit: u32,
    crash_signal: u32,
    nonterminal_stop: u32,
};

pub const PollResult = union(enum) {
    running,
    observation: Observation,
    no_child,
    failed: ProcessError,
};

pub const TerminateResult = union(enum) {
    accepted: TerminationAction,
    failed: ProcessError,
};

fn decodeError(category: u32, native_code: u32) ProcessError {
    return .{
        .category = std.enums.fromInt(ErrorCategory, category) orelse .system,
        .native_code = native_code,
    };
}

pub fn forceTerminate(id: std.process.Child.Id) TerminateResult {
    const result = os_api.processForceTerminate(os_api.processToken(id));
    if (result.accepted == 0) {
        return .{ .failed = decodeError(result.err, result.native_error) };
    }
    const action: TerminationAction = switch (result.action_kind) {
        1 => .{ .signal = result.action_value },
        2 => .{ .exit_code = result.action_value },
        else => return .{ .failed = .{ .category = .system, .native_code = result.native_error } },
    };
    return .{ .accepted = action };
}

pub fn classify(observation: Observation, successful_action: ?TerminationAction) ProcessOutcome {
    return switch (observation) {
        .exited => |code| if (code == 0)
            .clean_stop
        else if (successful_action != null and successful_action.? == .exit_code and successful_action.?.exit_code == code)
            .intentional_termination
        else
            .{ .crash_exit = code },
        .signaled => |signal| if (successful_action != null and successful_action.? == .signal and successful_action.?.signal == signal)
            .intentional_termination
        else
            .{ .crash_signal = signal },
        .stopped => |signal| .{ .nonterminal_stop = signal },
    };
}

pub fn tryReapNoHang(child: *std.process.Child) PollResult {
    const id = child.id orelse return .no_child;
    const result = os_api.processReapNoHang(os_api.processToken(id));
    return switch (result.kind) {
        0 => .running,
        1 => terminal: {
            const observation: Observation = .{ .exited = result.exit_code };
            os_api.processRelease(child);
            break :terminal .{ .observation = observation };
        },
        2 => terminal: {
            const observation: Observation = .{ .signaled = result.signal };
            os_api.processRelease(child);
            break :terminal .{ .observation = observation };
        },
        3 => .{ .observation = .{ .stopped = result.signal } },
        4 => detached: {
            os_api.processRelease(child);
            break :detached .no_child;
        },
        else => .{ .failed = decodeError(result.err, result.native_error) },
    };
}
