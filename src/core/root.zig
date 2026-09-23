//! core 对外入口：room 只应 import 本文件。
pub const types = @import("types.zig");
pub const Rules = @import("rules.zig").Rules;
pub const Desk = @import("desk.zig").Desk;
pub const PendingRef = @import("desk.zig").PendingRef;
pub const GamePhase = @import("desk.zig").GamePhase;
pub const Action = types.Action;
pub const Event = types.Event;
pub const Outcome = types.Outcome;
pub const Seat = types.Seat;
pub const CAPACITY = types.CAPACITY;
pub const ActionRequest = types.ActionRequest;
pub const ActionResolved = types.ActionResolved;
pub const TimeBudget = types.TimeBudget;
