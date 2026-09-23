//! MJAI 差分引擎：stdin JSONL → stdout JSONL。供 `harness/diff` 领导进程驱动。
//!
//!   {"op":"start","paishan":[136 mjai],"oya":0,"bakaze":"E","kyoku":1}
//!   {"op":"act","seat":0,"action":{"type":"dahai","pai":"1m","tsumogiri":true,"request_id":1}}
//!   {"op":"legal","seat":0}
//!   {"op":"quit"}
const std = @import("std");
const types = @import("core/types.zig");
const kyoku_mod = @import("core/kyoku.zig");
const engine = @import("core/engine/root.zig");
const wall = @import("core/engine/wall.zig");
const protocol = @import("room/protocol.zig");
const rules_mod = @import("core/rules.zig");

const Kyoku = kyoku_mod.Kyoku;
const Event = types.Event;
const Action = types.Action;
const Seat = types.Seat;
const Pai = types.Pai;
const WALL_LEN = kyoku_mod.WALL_LEN;
const LIVE_WALL_LEN = kyoku_mod.LIVE_WALL_LEN;
const DORA_MARKER_CAP = kyoku_mod.DORA_MARKER_CAP;
const CAPACITY = types.CAPACITY;

const ALL_PAI = [_][]const u8{
    "1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m",
    "1p", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p",
    "1s", "2s", "3s", "4s", "5s", "6s", "7s", "8s", "9s",
    "5mr", "5pr", "5sr",
    "E", "S", "W", "N", "P", "F", "C",
};

fn internPai(s: []const u8) ?Pai {
    for (ALL_PAI) |k| {
        if (std.mem.eql(u8, k, s)) return k;
    }
    return null;
}

/// 外部给的 136 张序（下标 0=首摸）→ 本引擎 tiles 布局。
fn mapPaishanToTiles(paishan: *const [WALL_LEN]Pai, out: *[WALL_LEN]Pai) void {
    @memset(out, "?");
    var n: u8 = 0;
    while (n < LIVE_WALL_LEN) : (n += 1) {
        out[wall.liveTileIndex(n)] = paishan[n];
    }
    var i: u8 = 0;
    while (i < DORA_MARKER_CAP) : (i += 1) {
        out[wall.doraTopIndex(i)] = paishan[131 - 2 * i];
        out[wall.uraBottomIndex(i)] = paishan[130 - 2 * i];
    }
    out[wall.rinshanTileIndex(0)] = paishan[135];
    out[wall.rinshanTileIndex(1)] = paishan[134];
    out[wall.rinshanTileIndex(2)] = paishan[133];
    out[wall.rinshanTileIndex(3)] = paishan[132];
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var ky = Kyoku.init();
    ky.rules = rules_mod.Rules.riichienv();
    var in_buf: [512 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &in_buf);
    const stdin = &stdin_reader.interface;

    while (true) {
        const line = (try stdin.takeDelimiter('\n')) orelse break;
        const trimmed = std.mem.trimEnd(u8, line, "\r");
        if (trimmed.len == 0) continue;

        var should_quit = false;
        const reply = handleLine(gpa, &ky, trimmed, &should_quit) catch |e| blk: {
            break :blk try std.fmt.allocPrint(gpa, "{{\"ok\":false,\"error\":\"{s}\"}}", .{@errorName(e)});
        };
        defer gpa.free(reply);
        try std.Io.File.stdout().writeStreamingAll(init.io, reply);
        try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
        if (should_quit) break;
    }
}

fn handleLine(gpa: std.mem.Allocator, ky: *Kyoku, line: []const u8, should_quit: *bool) ![]u8 {
    should_quit.* = false;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{ .allocate = .alloc_if_needed });
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.BadRequest;
    const op = root.object.get("op") orelse return error.BadRequest;
    if (op != .string) return error.BadRequest;

    if (std.mem.eql(u8, op.string, "quit")) {
        should_quit.* = true;
        return try std.fmt.allocPrint(gpa, "{{\"ok\":true,\"phase\":\"{s}\",\"scores\":[{d},{d},{d},{d}]}}", .{
            @tagName(ky.phase),
            ky.scores[0],
            ky.scores[1],
            ky.scores[2],
            ky.scores[3],
        });
    }

    if (std.mem.eql(u8, op.string, "start")) {
        // 差分固定用 riichienv preset（每局 start 重申，防状态残留）
        ky.rules = rules_mod.Rules.riichienv();
        var paishan: [WALL_LEN]Pai = undefined;
        const arr = root.object.get("paishan") orelse return error.BadRequest;
        if (arr != .array or arr.array.items.len != WALL_LEN) return error.BadRequest;
        for (arr.array.items, 0..) |item, i| {
            if (item != .string) return error.BadRequest;
            paishan[i] = internPai(item.string) orelse return error.BadRequest;
        }
        if (root.object.get("oya")) |oya_v| {
            if (oya_v == .integer) ky.oya = @intCast(oya_v.integer);
        }
        if (root.object.get("kyoku")) |k_v| {
            if (k_v == .integer) ky.kyoku = @intCast(k_v.integer);
        }
        if (root.object.get("bakaze")) |b_v| {
            if (b_v == .string) ky.bakaze = internPai(b_v.string) orelse ky.bakaze;
        }
        if (root.object.get("honba")) |h_v| {
            if (h_v == .integer) ky.honba = @intCast(h_v.integer);
        }
        if (root.object.get("kyotaku")) |t_v| {
            if (t_v == .integer) ky.kyotaku = @intCast(t_v.integer);
        }
        if (root.object.get("scores")) |scores_v| {
            if (scores_v == .array and scores_v.array.items.len == 4) {
                for (scores_v.array.items, 0..) |item, i| {
                    if (item == .integer) ky.scores[i] = @intCast(item.integer);
                }
            }
        }
        var ev_buf: [32]Event = undefined;
        var mapped: [WALL_LEN]Pai = undefined;
        mapPaishanToTiles(&paishan, &mapped);
        engine.loadWall(ky, &mapped);
        const evs = engine.onStartLoadedWall(ky, &ev_buf);
        return try encodeOkState(gpa, ky, evs);
    }

    if (std.mem.eql(u8, op.string, "replay_kyoku")) {
        // 整局回放：一次 RPC 跑完 start + 全部着法，回传事件与每步 legal_keys
        ky.rules = rules_mod.Rules.riichienv();
        var paishan: [WALL_LEN]Pai = undefined;
        const arr = root.object.get("paishan") orelse return error.BadRequest;
        if (arr != .array or arr.array.items.len != WALL_LEN) return error.BadRequest;
        for (arr.array.items, 0..) |item, i| {
            if (item != .string) return error.BadRequest;
            paishan[i] = internPai(item.string) orelse return error.BadRequest;
        }
        if (root.object.get("oya")) |oya_v| {
            if (oya_v == .integer) ky.oya = @intCast(oya_v.integer);
        }
        if (root.object.get("kyoku")) |k_v| {
            if (k_v == .integer) ky.kyoku = @intCast(k_v.integer);
        }
        if (root.object.get("bakaze")) |b_v| {
            if (b_v == .string) ky.bakaze = internPai(b_v.string) orelse ky.bakaze;
        }
        if (root.object.get("honba")) |h_v| {
            if (h_v == .integer) ky.honba = @intCast(h_v.integer);
        }
        if (root.object.get("kyotaku")) |t_v| {
            if (t_v == .integer) ky.kyotaku = @intCast(t_v.integer);
        }
        if (root.object.get("scores")) |scores_v| {
            if (scores_v == .array and scores_v.array.items.len == 4) {
                for (scores_v.array.items, 0..) |item, i| {
                    if (item == .integer) ky.scores[i] = @intCast(item.integer);
                }
            }
        }
        const steps_v = root.object.get("steps") orelse return error.BadRequest;
        if (steps_v != .array) return error.BadRequest;

        var mapped: [WALL_LEN]Pai = undefined;
        mapPaishanToTiles(&paishan, &mapped);
        engine.loadWall(ky, &mapped);

        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        try out.appendSlice(gpa, "{\"ok\":true,\"events\":[");
        var enc_buf: [8192]u8 = undefined;
        var n_total: usize = 0;

        var step_keys: std.ArrayList(u8) = .empty;
        defer step_keys.deinit(gpa);
        try step_keys.appendSlice(gpa, "[");

        var start_buf: [32]Event = undefined;
        const start_evs = engine.onStartLoadedWall(ky, &start_buf);
        for (start_evs) |ev| {
            if (n_total != 0) try out.append(gpa, ',');
            const json = try protocol.encodeEvent(ev, &enc_buf);
            try out.appendSlice(gpa, json);
            n_total += 1;
        }

        for (steps_v.array.items, 0..) |step_item, step_i| {
            if (step_item != .array) return error.BadRequest;
            if (step_i != 0) try step_keys.append(gpa, ',');
            try appendLegalKeysObject(gpa, ky, &step_keys);

            var ev_buf: [128]Event = undefined;
            var n_ev: usize = 0;
            for (step_item.array.items) |item| {
                if (item != .object) return error.BadRequest;
                const seat_v = item.object.get("seat") orelse return error.BadRequest;
                if (seat_v != .integer) return error.BadRequest;
                const seat: Seat = @intCast(seat_v.integer);
                const action_v = item.object.get("action") orelse return error.BadRequest;
                const action = try actionFromJsonValue(action_v);
                const produced = try engine.apply(ky, seat, action, ev_buf[n_ev..]);
                n_ev += produced.len;
            }
            for (ev_buf[0..n_ev]) |ev| {
                if (n_total != 0) try out.append(gpa, ',');
                const json = try protocol.encodeEvent(ev, &enc_buf);
                try out.appendSlice(gpa, json);
                n_total += 1;
            }
        }
        try step_keys.append(gpa, ']');
        try out.appendSlice(gpa, "],\"step_legal_keys\":");
        try out.appendSlice(gpa, step_keys.items);
        try out.append(gpa, '}');
        return try out.toOwnedSlice(gpa);
    }

    if (std.mem.eql(u8, op.string, "act")) {
        const seat_v = root.object.get("seat") orelse return error.BadRequest;
        if (seat_v != .integer) return error.BadRequest;
        const seat: Seat = @intCast(seat_v.integer);
        const action_v = root.object.get("action") orelse return error.BadRequest;

        var aw: std.Io.Writer.Allocating = .init(gpa);
        defer aw.deinit();
        try std.json.Stringify.value(action_v, .{}, &aw.writer);
        const action_json = aw.written();

        const action_line = blk: {
            if (std.mem.indexOf(u8, action_json, "request_id") != null) break :blk action_json;
            if (action_json.len < 2 or action_json[0] != '{') return error.BadRequest;
            break :blk try std.fmt.allocPrint(gpa, "{s}\"request_id\":1,{s}", .{
                action_json[0..1],
                action_json[1..],
            });
        };
        defer if (action_line.ptr != action_json.ptr) gpa.free(action_line);

        const parsed_act = try protocol.parseAction(gpa, action_line);
        var ev_buf: [64]Event = undefined;
        const evs = try engine.apply(ky, seat, parsed_act.action, &ev_buf);
        return try encodeOkState(gpa, ky, evs);
    }

    if (std.mem.eql(u8, op.string, "acts")) {
        // 批量着法（应手窗等多座位一次提交）
        const arr = root.object.get("actions") orelse return error.BadRequest;
        if (arr != .array) return error.BadRequest;
        var ev_buf: [128]Event = undefined;
        var n_ev: usize = 0;
        for (arr.array.items) |item| {
            if (item != .object) return error.BadRequest;
            const seat_v = item.object.get("seat") orelse return error.BadRequest;
            if (seat_v != .integer) return error.BadRequest;
            const seat: Seat = @intCast(seat_v.integer);
            const action_v = item.object.get("action") orelse return error.BadRequest;
            var aw: std.Io.Writer.Allocating = .init(gpa);
            defer aw.deinit();
            try std.json.Stringify.value(action_v, .{}, &aw.writer);
            const action_json = aw.written();
            const action_line = blk: {
                if (std.mem.indexOf(u8, action_json, "request_id") != null) break :blk action_json;
                if (action_json.len < 2 or action_json[0] != '{') return error.BadRequest;
                break :blk try std.fmt.allocPrint(gpa, "{s}\"request_id\":1,{s}", .{
                    action_json[0..1],
                    action_json[1..],
                });
            };
            defer if (action_line.ptr != action_json.ptr) gpa.free(action_line);
            const parsed_act = try protocol.parseAction(gpa, action_line);
            const produced = try engine.apply(ky, seat, parsed_act.action, ev_buf[n_ev..]);
            n_ev += produced.len;
        }
        return try encodeOkState(gpa, ky, ev_buf[0..n_ev]);
    }

    if (std.mem.eql(u8, op.string, "legal")) {
        const seat_v = root.object.get("seat") orelse return error.BadRequest;
        if (seat_v != .integer) return error.BadRequest;
        const seat: Seat = @intCast(seat_v.integer);
        var act_buf: [64]Action = undefined;
        const acts = engine.legalActions(ky, seat, &act_buf);
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        try out.appendSlice(gpa, "{\"ok\":true,\"actions\":[");
        for (acts, 0..) |a, i| {
            if (i != 0) try out.append(gpa, ',');
            try appendActionJson(&out, gpa, a);
        }
        try out.appendSlice(gpa, "]}");
        return try out.toOwnedSlice(gpa);
    }

    return error.BadRequest;
}

fn actionFromJsonValue(v: std.json.Value) !Action {
    if (v != .object) return error.BadRequest;
    const typ_v = v.object.get("type") orelse return error.BadRequest;
    if (typ_v != .string) return error.BadRequest;
    const typ = typ_v.string;

    if (std.mem.eql(u8, typ, "none")) return .none;
    if (std.mem.eql(u8, typ, "reach")) return .reach;
    if (std.mem.eql(u8, typ, "ryukyoku")) return .ryukyoku;
    if (std.mem.eql(u8, typ, "hora")) {
        var target: ?Seat = null;
        if (v.object.get("target")) |t| {
            if (t == .integer) {
                if (t.integer < 0 or t.integer >= CAPACITY) return error.BadRequest;
                target = @intCast(t.integer);
            }
        }
        var pai: ?Pai = null;
        if (v.object.get("pai")) |p| {
            if (p == .string) pai = internPai(p.string) orelse return error.BadRequest;
        }
        return .{ .hora = .{ .target = target, .pai = pai } };
    }
    if (std.mem.eql(u8, typ, "dahai")) {
        const pai_v = v.object.get("pai") orelse return error.BadRequest;
        if (pai_v != .string) return error.BadRequest;
        const pai = internPai(pai_v.string) orelse return error.BadRequest;
        var tsumogiri = false;
        if (v.object.get("tsumogiri")) |t| {
            if (t == .bool) tsumogiri = t.bool;
        }
        return .{ .dahai = .{ .pai = pai, .tsumogiri = tsumogiri } };
    }
    if (std.mem.eql(u8, typ, "chi") or std.mem.eql(u8, typ, "pon")) {
        const pai_v = v.object.get("pai") orelse return error.BadRequest;
        if (pai_v != .string) return error.BadRequest;
        const pai = internPai(pai_v.string) orelse return error.BadRequest;
        var cons: [2]Pai = undefined;
        try fillConsumed(v.object.get("consumed"), &cons);
        if (std.mem.eql(u8, typ, "chi")) return .{ .chi = .{ .pai = pai, .consumed = cons } };
        return .{ .pon = .{ .pai = pai, .consumed = cons } };
    }
    if (std.mem.eql(u8, typ, "daiminkan") or std.mem.eql(u8, typ, "kakan")) {
        const pai_v = v.object.get("pai") orelse return error.BadRequest;
        if (pai_v != .string) return error.BadRequest;
        const pai = internPai(pai_v.string) orelse return error.BadRequest;
        var cons: [3]Pai = undefined;
        try fillConsumed(v.object.get("consumed"), &cons);
        if (std.mem.eql(u8, typ, "daiminkan")) return .{ .daiminkan = .{ .pai = pai, .consumed = cons } };
        return .{ .kakan = .{ .pai = pai, .consumed = cons } };
    }
    if (std.mem.eql(u8, typ, "ankan")) {
        var cons: [4]Pai = undefined;
        try fillConsumed(v.object.get("consumed"), &cons);
        return .{ .ankan = .{ .consumed = cons } };
    }
    return error.BadRequest;
}

fn fillConsumed(v: ?std.json.Value, out: []Pai) !void {
    const arr = v orelse return error.BadRequest;
    if (arr != .array or arr.array.items.len != out.len) return error.BadRequest;
    for (arr.array.items, 0..) |item, i| {
        if (item != .string) return error.BadRequest;
        out[i] = internPai(item.string) orelse return error.BadRequest;
    }
}

fn appendLegalKeysObject(gpa: std.mem.Allocator, ky: *Kyoku, out: *std.ArrayList(u8)) !void {
    try out.append(gpa, '{');
    var seat_buf: [CAPACITY]Seat = undefined;
    const needing = engine.seatsNeedingAction(ky, &seat_buf);
    var act_buf: [64]Action = undefined;
    for (needing, 0..) |seat, si| {
        if (si != 0) try out.append(gpa, ',');
        var key_buf: [16]u8 = undefined;
        const key = try std.fmt.bufPrint(&key_buf, "\"{d}\":[", .{seat});
        try out.appendSlice(gpa, key);
        const acts = engine.legalActions(ky, seat, &act_buf);
        for (acts, 0..) |a, i| {
            if (i != 0) try out.append(gpa, ',');
            try appendLegalKeyJson(out, gpa, a);
        }
        try out.append(gpa, ']');
    }
    try out.append(gpa, '}');
}

fn encodeOkState(gpa: std.mem.Allocator, ky: *Kyoku, evs: []const Event) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "{\"ok\":true,\"events\":[");
    var enc_buf: [8192]u8 = undefined;
    for (evs, 0..) |ev, i| {
        if (i != 0) try out.append(gpa, ',');
        const json = try protocol.encodeEvent(ev, &enc_buf);
        try out.appendSlice(gpa, json);
    }
    // 紧凑合法着键（与 harness/diff/compare.action_key 对齐），避免每步回传整表 dahai JSON
    try out.appendSlice(gpa, "],\"legal_keys\":{");

    var seat_buf: [CAPACITY]Seat = undefined;
    const needing = engine.seatsNeedingAction(ky, &seat_buf);
    var act_buf: [64]Action = undefined;
    for (needing, 0..) |seat, si| {
        if (si != 0) try out.append(gpa, ',');
        var key_buf: [16]u8 = undefined;
        const key = try std.fmt.bufPrint(&key_buf, "\"{d}\":[", .{seat});
        try out.appendSlice(gpa, key);
        const acts = engine.legalActions(ky, seat, &act_buf);
        for (acts, 0..) |a, i| {
            if (i != 0) try out.append(gpa, ',');
            try appendLegalKeyJson(&out, gpa, a);
        }
        try out.append(gpa, ']');
    }
    try out.appendSlice(gpa, "}}");
    return try out.toOwnedSlice(gpa);
}

fn appendLegalKeyJson(out: *std.ArrayList(u8), gpa: std.mem.Allocator, a: Action) !void {
    // 与 Python action_key 同构的短字符串
    const piece = switch (a) {
        .none => try gpa.dupe(u8, "\"none\""),
        .reach => try gpa.dupe(u8, "\"reach\""),
        .ryukyoku => try gpa.dupe(u8, "\"ryukyoku\""),
        .hora => try gpa.dupe(u8, "\"hora\""),
        .dahai => |d| try std.fmt.allocPrint(gpa, "\"dahai:{s}:{d}\"", .{
            d.pai,
            @as(u8, if (d.tsumogiri) 1 else 0),
        }),
        .chi => |c| blk: {
            var cons = c.consumed;
            sort2(&cons);
            break :blk try std.fmt.allocPrint(gpa, "\"chi:{s}:{s}+{s}\"", .{ c.pai, cons[0], cons[1] });
        },
        .pon => |c| blk: {
            var cons = c.consumed;
            sort2(&cons);
            break :blk try std.fmt.allocPrint(gpa, "\"pon:{s}:{s}+{s}\"", .{ c.pai, cons[0], cons[1] });
        },
        .daiminkan => |c| blk: {
            var cons = c.consumed;
            sort3(&cons);
            break :blk try std.fmt.allocPrint(gpa, "\"daiminkan:{s}:{s}+{s}+{s}\"", .{
                c.pai, cons[0], cons[1], cons[2],
            });
        },
        .ankan => |c| blk: {
            var cons = c.consumed;
            sort4(&cons);
            break :blk try std.fmt.allocPrint(gpa, "\"ankan:{s}+{s}+{s}+{s}\"", .{
                cons[0], cons[1], cons[2], cons[3],
            });
        },
        .kakan => |c| blk: {
            var cons = c.consumed;
            sort3(&cons);
            break :blk try std.fmt.allocPrint(gpa, "\"kakan:{s}:{s}+{s}+{s}\"", .{
                c.pai, cons[0], cons[1], cons[2],
            });
        },
    };
    defer gpa.free(piece);
    try out.appendSlice(gpa, piece);
}

fn sort2(a: *[2]Pai) void {
    if (std.mem.order(u8, a[0], a[1]) == .gt) {
        const t = a[0];
        a[0] = a[1];
        a[1] = t;
    }
}

fn sort3(a: *[3]Pai) void {
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        var j: usize = i + 1;
        while (j < 3) : (j += 1) {
            if (std.mem.order(u8, a[i], a[j]) == .gt) {
                const t = a[i];
                a[i] = a[j];
                a[j] = t;
            }
        }
    }
}

fn sort4(a: *[4]Pai) void {
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var j: usize = i + 1;
        while (j < 4) : (j += 1) {
            if (std.mem.order(u8, a[i], a[j]) == .gt) {
                const t = a[i];
                a[i] = a[j];
                a[j] = t;
            }
        }
    }
}

fn appendActionJson(out: *std.ArrayList(u8), gpa: std.mem.Allocator, a: Action) !void {
    const piece = switch (a) {
        .none => try gpa.dupe(u8, "{\"type\":\"none\"}"),
        .reach => try gpa.dupe(u8, "{\"type\":\"reach\"}"),
        .ryukyoku => try gpa.dupe(u8, "{\"type\":\"ryukyoku\"}"),
        .hora => try gpa.dupe(u8, "{\"type\":\"hora\"}"),
        .dahai => |d| try std.fmt.allocPrint(gpa, "{{\"type\":\"dahai\",\"pai\":\"{s}\",\"tsumogiri\":{s}}}", .{
            d.pai,
            if (d.tsumogiri) "true" else "false",
        }),
        .chi => |c| try std.fmt.allocPrint(gpa, "{{\"type\":\"chi\",\"pai\":\"{s}\",\"consumed\":[\"{s}\",\"{s}\"]}}", .{
            c.pai, c.consumed[0], c.consumed[1],
        }),
        .pon => |c| try std.fmt.allocPrint(gpa, "{{\"type\":\"pon\",\"pai\":\"{s}\",\"consumed\":[\"{s}\",\"{s}\"]}}", .{
            c.pai, c.consumed[0], c.consumed[1],
        }),
        .daiminkan => |c| try std.fmt.allocPrint(gpa, "{{\"type\":\"daiminkan\",\"pai\":\"{s}\",\"consumed\":[\"{s}\",\"{s}\",\"{s}\"]}}", .{
            c.pai, c.consumed[0], c.consumed[1], c.consumed[2],
        }),
        .ankan => |c| try std.fmt.allocPrint(gpa, "{{\"type\":\"ankan\",\"consumed\":[\"{s}\",\"{s}\",\"{s}\",\"{s}\"]}}", .{
            c.consumed[0], c.consumed[1], c.consumed[2], c.consumed[3],
        }),
        .kakan => |c| try std.fmt.allocPrint(gpa, "{{\"type\":\"kakan\",\"pai\":\"{s}\",\"consumed\":[\"{s}\",\"{s}\",\"{s}\"]}}", .{
            c.pai, c.consumed[0], c.consumed[1], c.consumed[2],
        }),
    };
    defer gpa.free(piece);
    try out.appendSlice(gpa, piece);
}
