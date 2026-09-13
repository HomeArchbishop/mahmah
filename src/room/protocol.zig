const std = @import("std");
const core = @import("../core/root.zig");
const types = @import("../core/types.zig");
const Event = core.Event;
const Action = core.Action;
const Seat = types.Seat;
const Pai = types.Pai;
const CAPACITY = types.CAPACITY;
const TEHAI_LEN = types.TEHAI_LEN;

/// MJAI 牌局文本编解码。遮罩按观察者座位在 encodeEventForSeat 完成。

const ALL_PAI = [_][]const u8{
    "1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m",
    "1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p",
    "1s", "2s", "3s", "4s", "5s", "6s", "7s", "8s", "9s",
    "5mr", "5pr", "5sr",
    "E", "S", "W", "N", "P", "F", "C",
    "?",
};

fn internPai(pai: []const u8) ?Pai {
    for (ALL_PAI) |k| {
        if (std.mem.eql(u8, k, pai)) return k;
    }
    return null;
}

fn append(buf: []u8, pos: *usize, piece: []const u8) !void {
    if (pos.* + piece.len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[pos.*..][0..piece.len], piece);
    pos.* += piece.len;
}

fn appendFmt(buf: []u8, pos: *usize, comptime fmt: []const u8, args: anytype) !void {
    const written = try std.fmt.bufPrint(buf[pos.*..], fmt, args);
    pos.* += written.len;
}

fn encodePaiList(pais: []const Pai, buf: []u8, pos: *usize) !void {
    try append(buf, pos, "[");
    for (pais, 0..) |p, i| {
        if (i != 0) try append(buf, pos, ",");
        try appendFmt(buf, pos, "\"{s}\"", .{p});
    }
    try append(buf, pos, "]");
}

fn encodeTehaisMasked(tehais: types.Tehais, viewer: Seat, buf: []u8, pos: *usize) !void {
    const hidden = [_]Pai{"?"} ** TEHAI_LEN;
    try append(buf, pos, "[");
    for (tehais, 0..) |hand, i| {
        if (i != 0) try append(buf, pos, ",");
        if (i == viewer) {
            try encodePaiList(&hand, buf, pos);
        } else {
            try encodePaiList(&hidden, buf, pos);
        }
    }
    try append(buf, pos, "]");
}

fn encodeTehaisRaw(tehais: types.Tehais, buf: []u8, pos: *usize) !void {
    try append(buf, pos, "[");
    for (tehais, 0..) |hand, i| {
        if (i != 0) try append(buf, pos, ",");
        try encodePaiList(&hand, buf, pos);
    }
    try append(buf, pos, "]");
}

/// 无遮罩编码（仅用于不依赖观察者的事件，或测试）。
pub fn encodeEvent(event: Event, buf: []u8) ![]const u8 {
    return encodeEventForSeat(event, null, buf);
}

/// `viewer == null`：不遮罩。`viewer == seat`：tehais / 他人 tsumo 按 MJAI 遮罩。
pub fn encodeEventForSeat(event: Event, viewer: ?Seat, buf: []u8) ![]const u8 {
    var pos: usize = 0;
    switch (event) {
        .start_game => try append(buf, &pos, "{\"type\":\"start_game\"}"),
        .start_kyoku => |k| {
            try appendFmt(buf, &pos, "{{\"type\":\"start_kyoku\",\"bakaze\":\"{s}\",\"dora_marker\":", .{k.bakaze});
            try encodePaiList(k.dora_markers, buf, &pos);
            try appendFmt(buf, &pos, ",\"kyoku\":{d},\"honba\":{d},\"kyotaku\":{d},\"oya\":{d},\"tehais\":", .{
                k.kyoku, k.honba, k.kyotaku, k.oya,
            });
            if (viewer) |v| {
                try encodeTehaisMasked(k.tehais, v, buf, &pos);
            } else {
                try encodeTehaisRaw(k.tehais, buf, &pos);
            }
            try append(buf, &pos, "}");
        },
        .tsumo => |t| {
            const pai: Pai = if (viewer) |v|
                (if (v == t.actor) t.pai else "?")
            else
                t.pai;
            try appendFmt(buf, &pos, "{{\"type\":\"tsumo\",\"actor\":{d},\"pai\":\"{s}\"}}", .{ t.actor, pai });
        },
        .dahai => |d| try appendFmt(buf, &pos, "{{\"type\":\"dahai\",\"actor\":{d},\"pai\":\"{s}\",\"tsumogiri\":{s}}}", .{
            d.actor, d.pai, if (d.tsumogiri) "true" else "false",
        }),
        .chi => |c| {
            try appendFmt(buf, &pos, "{{\"type\":\"chi\",\"actor\":{d},\"target\":{d},\"pai\":\"{s}\",\"consumed\":", .{ c.actor, c.target, c.pai });
            try encodePaiList(&c.consumed, buf, &pos);
            try append(buf, &pos, "}");
        },
        .pon => |c| {
            try appendFmt(buf, &pos, "{{\"type\":\"pon\",\"actor\":{d},\"target\":{d},\"pai\":\"{s}\",\"consumed\":", .{ c.actor, c.target, c.pai });
            try encodePaiList(&c.consumed, buf, &pos);
            try append(buf, &pos, "}");
        },
        .daiminkan => |c| {
            try appendFmt(buf, &pos, "{{\"type\":\"daiminkan\",\"actor\":{d},\"target\":{d},\"pai\":\"{s}\",\"consumed\":", .{ c.actor, c.target, c.pai });
            try encodePaiList(&c.consumed, buf, &pos);
            try append(buf, &pos, "}");
        },
        .ankan => |c| {
            try appendFmt(buf, &pos, "{{\"type\":\"ankan\",\"actor\":{d},\"consumed\":", .{c.actor});
            try encodePaiList(&c.consumed, buf, &pos);
            try append(buf, &pos, "}");
        },
        .kakan => |c| {
            try appendFmt(buf, &pos, "{{\"type\":\"kakan\",\"actor\":{d},\"pai\":\"{s}\",\"consumed\":", .{ c.actor, c.pai });
            try encodePaiList(&c.consumed, buf, &pos);
            try append(buf, &pos, "}");
        },
        .dora => |d| try appendFmt(buf, &pos, "{{\"type\":\"dora\",\"dora_marker\":\"{s}\"}}", .{d.dora_marker}),
        .reach => |r| try appendFmt(buf, &pos, "{{\"type\":\"reach\",\"actor\":{d}}}", .{r.actor}),
        .reach_accepted => |r| try appendFmt(buf, &pos, "{{\"type\":\"reach_accepted\",\"actor\":{d}}}", .{r.actor}),
        .hora => |h| try appendFmt(buf, &pos, "{{\"type\":\"hora\",\"actor\":{d},\"target\":{d},\"pai\":\"{s}\"}}", .{ h.actor, h.target, h.pai }),
        .ryukyoku => |r| {
            try appendFmt(buf, &pos, "{{\"type\":\"ryukyoku\",\"reason\":\"{s}\",\"deltas\":[{d},{d},{d},{d}]", .{
                r.reason, r.deltas[0], r.deltas[1], r.deltas[2], r.deltas[3],
            });
            if (r.tehais) |tehais| {
                try append(buf, &pos, ",\"tehais\":");
                if (viewer) |v| {
                    try encodeTehaisMasked(tehais, v, buf, &pos);
                } else {
                    try encodeTehaisRaw(tehais, buf, &pos);
                }
            }
            try append(buf, &pos, "}");
        },
        .end_kyoku => try append(buf, &pos, "{\"type\":\"end_kyoku\"}"),
        .end_game => |g| try appendFmt(buf, &pos, "{{\"type\":\"end_game\",\"scores\":[{d},{d},{d},{d}]}}", .{
            g.scores[0], g.scores[1], g.scores[2], g.scores[3],
        }),
        .action_requested => |r| return encodeActionRequested(r, buf),
        .action_resolved => |r| return encodeActionResolved(r, buf),
    }
    return buf[0..pos];
}

pub fn encodeStartGame(seat: Seat, buf: []u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"start_game\",\"id\":{d}}}", .{seat});
}

fn encodeActionRequested(r: types.ActionRequest, buf: []u8) ![]const u8 {
    var pos: usize = 0;
    try appendFmt(buf, &pos, "{{\"type\":\"request_action\",\"request_id\":{d},\"time\":{{\"grace_ms\":{d},\"bank_ms\":{d},\"deadline_ms\":{d}}},\"possible_actions\":[", .{
        r.request_id, r.time.grace_ms, r.time.bank_ms, r.time.deadline_ms,
    });
    for (r.legal_actions, 0..) |action, i| {
        if (i != 0) try append(buf, &pos, ",");
        const piece = try encodePossibleAction(action, buf[pos..]);
        pos += piece.len;
    }
    try append(buf, &pos, "]");
    if (r.observation) |obs| {
        try appendFmt(buf, &pos, ",\"observation\":\"{s}\"", .{obs});
    }
    try append(buf, &pos, "}");
    return buf[0..pos];
}

fn encodeActionResolved(r: types.ActionResolved, buf: []u8) ![]const u8 {
    var pos: usize = 0;
    const status = switch (r.status) {
        .accepted => "accepted",
        .rejected => "rejected",
        .unparseable => "unparseable",
        .stale => "stale",
        .defaulted => "defaulted",
    };
    try appendFmt(buf, &pos, "{{\"type\":\"action_ack\",\"request_id\":{d},\"status\":\"{s}\",\"elapsed_ms\":{d},\"bank_consumed_ms\":{d},\"bank_ms\":{d}", .{
        r.request_id, status, r.elapsed_ms, r.bank_consumed_ms, r.bank_ms,
    });
    if (r.status == .defaulted) {
        if (r.action) |action| {
            try append(buf, &pos, ",\"action\":");
            const piece = try encodePossibleAction(action, buf[pos..]);
            pos += piece.len;
        }
    }
    if (r.status == .rejected) {
        if (r.attempted) |attempted| {
            try append(buf, &pos, ",\"attempted\":");
            const piece = try encodePossibleAction(attempted, buf[pos..]);
            pos += piece.len;
        }
        if (r.reason) |reason| {
            try appendFmt(buf, &pos, ",\"reason\":\"{s}\"", .{reason});
        }
        if (r.legal_types) |types_list| {
            try append(buf, &pos, ",\"legal_types\":[");
            for (types_list, 0..) |t, i| {
                if (i != 0) try append(buf, &pos, ",");
                try appendFmt(buf, &pos, "\"{s}\"", .{t});
            }
            try append(buf, &pos, "]");
        }
    }
    if (r.status == .unparseable) {
        if (r.reason) |reason| {
            try appendFmt(buf, &pos, ",\"reason\":\"{s}\"", .{reason});
        }
    }
    try append(buf, &pos, "}");
    return buf[0..pos];
}

/// possible_actions / ack 内嵌着法：与参考示例一致（dahai 仅在 tsumogiri 时写出该字段）。
fn encodePossibleAction(action: Action, buf: []u8) ![]const u8 {
    var pos: usize = 0;
    switch (action) {
        .dahai => |d| {
            if (d.tsumogiri) {
                try appendFmt(buf, &pos, "{{\"type\":\"dahai\",\"pai\":\"{s}\",\"tsumogiri\":true}}", .{d.pai});
            } else {
                try appendFmt(buf, &pos, "{{\"type\":\"dahai\",\"pai\":\"{s}\"}}", .{d.pai});
            }
        },
        .chi => |c| {
            try appendFmt(buf, &pos, "{{\"type\":\"chi\",\"pai\":\"{s}\",\"consumed\":", .{c.pai});
            try encodePaiList(&c.consumed, buf, &pos);
            try append(buf, &pos, "}");
        },
        .pon => |c| {
            try appendFmt(buf, &pos, "{{\"type\":\"pon\",\"pai\":\"{s}\",\"consumed\":", .{c.pai});
            try encodePaiList(&c.consumed, buf, &pos);
            try append(buf, &pos, "}");
        },
        .daiminkan => |c| {
            try appendFmt(buf, &pos, "{{\"type\":\"daiminkan\",\"pai\":\"{s}\",\"consumed\":", .{c.pai});
            try encodePaiList(&c.consumed, buf, &pos);
            try append(buf, &pos, "}");
        },
        .ankan => |c| {
            try append(buf, &pos, "{\"type\":\"ankan\",\"consumed\":");
            try encodePaiList(&c.consumed, buf, &pos);
            try append(buf, &pos, "}");
        },
        .kakan => |c| {
            try appendFmt(buf, &pos, "{{\"type\":\"kakan\",\"pai\":\"{s}\",\"consumed\":", .{c.pai});
            try encodePaiList(&c.consumed, buf, &pos);
            try append(buf, &pos, "}");
        },
        .reach => try append(buf, &pos, "{\"type\":\"reach\"}"),
        .hora => |h| {
            try append(buf, &pos, "{\"type\":\"hora\"");
            if (h.target) |t| try appendFmt(buf, &pos, ",\"target\":{d}", .{t});
            if (h.pai) |p| try appendFmt(buf, &pos, ",\"pai\":\"{s}\"", .{p});
            try append(buf, &pos, "}");
        },
        .ryukyoku => try append(buf, &pos, "{\"type\":\"ryukyoku\"}"),
        .none => try append(buf, &pos, "{\"type\":\"none\"}"),
    }
    return buf[0..pos];
}

const Inbound = struct {
    @"type": []const u8,
    request_id: ?u32 = null,
    pai: ?[]const u8 = null,
    tsumogiri: ?bool = null,
    target: ?u8 = null,
    consumed: ?[][]const u8 = null,
};

pub const ParsedAction = struct {
    request_id: u32,
    action: Action,
};

fn parseConsumed(comptime N: usize, raw: ?[][]const u8) ![N]Pai {
    const list = raw orelse return error.BadRequest;
    if (list.len != N) return error.BadRequest;
    var out: [N]Pai = undefined;
    for (list, 0..) |p, i| {
        out[i] = internPai(p) orelse return error.BadRequest;
    }
    return out;
}

/// 仅抽出 request_id（用于 unparseable 路径）。
pub fn peekRequestId(allocator: std.mem.Allocator, data: []const u8) ?u32 {
    const parsed = std.json.parseFromSlice(struct { request_id: ?u32 = null }, allocator, data, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_if_needed,
    }) catch return null;
    defer parsed.deinit();
    return parsed.value.request_id;
}

/// 客户端上行 JSON → Action + request_id。未知 type / 缺字段 → BadRequest。
pub fn parseAction(allocator: std.mem.Allocator, data: []const u8) !ParsedAction {
    const parsed = try std.json.parseFromSlice(Inbound, allocator, data, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_if_needed,
    });
    defer parsed.deinit();
    const env = parsed.value;
    const request_id = env.request_id orelse return error.BadRequest;
    const typ = env.@"type";

    if (std.mem.eql(u8, typ, "none")) {
        return .{ .request_id = request_id, .action = .none };
    }
    if (std.mem.eql(u8, typ, "reach")) {
        return .{ .request_id = request_id, .action = .reach };
    }
    if (std.mem.eql(u8, typ, "ryukyoku")) {
        return .{ .request_id = request_id, .action = .ryukyoku };
    }
    if (std.mem.eql(u8, typ, "dahai")) {
        const pai = internPai(env.pai orelse return error.BadRequest) orelse return error.BadRequest;
        return .{
            .request_id = request_id,
            .action = .{ .dahai = .{ .pai = pai, .tsumogiri = env.tsumogiri orelse false } },
        };
    }
    if (std.mem.eql(u8, typ, "chi")) {
        const pai = internPai(env.pai orelse return error.BadRequest) orelse return error.BadRequest;
        return .{
            .request_id = request_id,
            .action = .{ .chi = .{ .pai = pai, .consumed = try parseConsumed(2, env.consumed) } },
        };
    }
    if (std.mem.eql(u8, typ, "pon")) {
        const pai = internPai(env.pai orelse return error.BadRequest) orelse return error.BadRequest;
        return .{
            .request_id = request_id,
            .action = .{ .pon = .{ .pai = pai, .consumed = try parseConsumed(2, env.consumed) } },
        };
    }
    if (std.mem.eql(u8, typ, "daiminkan")) {
        const pai = internPai(env.pai orelse return error.BadRequest) orelse return error.BadRequest;
        return .{
            .request_id = request_id,
            .action = .{ .daiminkan = .{ .pai = pai, .consumed = try parseConsumed(3, env.consumed) } },
        };
    }
    if (std.mem.eql(u8, typ, "ankan")) {
        return .{
            .request_id = request_id,
            .action = .{ .ankan = .{ .consumed = try parseConsumed(4, env.consumed) } },
        };
    }
    if (std.mem.eql(u8, typ, "kakan")) {
        const pai = internPai(env.pai orelse return error.BadRequest) orelse return error.BadRequest;
        return .{
            .request_id = request_id,
            .action = .{ .kakan = .{ .pai = pai, .consumed = try parseConsumed(3, env.consumed) } },
        };
    }
    if (std.mem.eql(u8, typ, "hora")) {
        var target: ?Seat = null;
        if (env.target) |t| {
            if (t >= CAPACITY) return error.BadRequest;
            target = @intCast(t);
        }
        var pai: ?Pai = null;
        if (env.pai) |p| {
            pai = internPai(p) orelse return error.BadRequest;
        }
        return .{ .request_id = request_id, .action = .{ .hora = .{ .target = target, .pai = pai } } };
    }
    return error.BadRequest;
}

test "mask tsumo for other seats" {
    const ev: Event = .{ .tsumo = .{ .actor = 0, .pai = "3m" } };
    var buf: [128]u8 = undefined;
    const self_view = try encodeEventForSeat(ev, 0, &buf);
    try std.testing.expect(std.mem.indexOf(u8, self_view, "\"pai\":\"3m\"") != null);
    var buf2: [128]u8 = undefined;
    const other = try encodeEventForSeat(ev, 1, &buf2);
    try std.testing.expect(std.mem.indexOf(u8, other, "\"pai\":\"?\"") != null);
}

test "action_ack rejected uses attempted" {
    const ev: Event = .{ .action_resolved = .{
        .request_id = 1,
        .status = .rejected,
        .attempted = .{ .dahai = .{ .pai = "9m" } },
        .reason = "Error: Illegal Action by Player 0",
        .legal_types = &[_][]const u8{"dahai"},
        .bank_ms = 0,
    } };
    var buf: [512]u8 = undefined;
    const json = try encodeEvent(ev, &buf);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"attempted\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"elapsed_ms\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"legal_types\":[\"dahai\"]") != null);
}

test "parse chi action" {
    const raw =
        \\{"type":"chi","request_id":7,"actor":1,"pai":"5m","consumed":["4m","6m"]}
    ;
    const parsed = try parseAction(std.testing.allocator, raw);
    try std.testing.expectEqual(@as(u32, 7), parsed.request_id);
    try std.testing.expect(parsed.action == .chi);
}
