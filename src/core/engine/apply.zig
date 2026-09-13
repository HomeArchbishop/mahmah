const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const discard = @import("discard.zig");
const response = @import("response.zig");
const hora = @import("hora.zig");
const kan = @import("kan.zig");
const round = @import("round.zig");
const Kyoku = kyoku_mod.Kyoku;
const Action = types.Action;
const Event = types.Event;
const Seat = types.Seat;
const ApplyError = types.ApplyError;

/// wait_act：一行委托到各路径模块。
pub fn applyWaitAct(ky: *Kyoku, seat: Seat, action: Action, out: []Event) ApplyError![]Event {
    if (seat != ky.turn) return error.IllegalAction;

    return switch (action) {
        .dahai => |d| discard.resolveDiscard(ky, seat, d.pai, d.tsumogiri, out),
        .reach => discard.applyReach(ky, seat, out),
        .hora => hora.applyTsumo(ky, seat, out),
        .ryukyoku => round.applyKyushu(ky, out),
        .ankan => |a| kan.applyAnkan(ky, seat, a.consumed, out),
        .kakan => |a| kan.applyKakan(ky, seat, a.pai, a.consumed, out),
        else => error.IllegalAction,
    };
}

pub fn applyWaitResponse(ky: *Kyoku, seat: Seat, action: Action, out: []Event) ApplyError![]Event {
    return response.applyWaitResponse(ky, seat, action, out);
}
