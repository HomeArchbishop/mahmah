const std = @import("std");
const httpz = @import("httpz");
const player_conn = @import("player_conn.zig");
const context = @import("context.zig");
const ids = @import("../shared/ids.zig");
const Lobby = @import("../lobby/lobby.zig").Lobby;
const RoomManager = @import("../room/room_manager.zig").RoomManager;

pub const Deps = struct {
    allocator: std.mem.Allocator,
    player_id_gen: *ids.PlayerIdGen,
    conn_id_gen: *ids.ConnIdGen,
    lobby: *Lobby,
    room_manager: *RoomManager,

    pub const WebsocketHandler = player_conn.PlayerConn;
};

pub fn wsLobby(deps: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    const player_id = deps.player_id_gen.nextReal();
    try upgrade(deps, req, res, player_id, .lobby);
}

pub fn wsRoom(deps: *Deps, req: *httpz.Request, res: *httpz.Response) !void {
    const room_id_str = req.param("room_id") orelse return badRequest(res);
    const room_id = std.fmt.parseInt(ids.RoomId, room_id_str, 10) catch return badRequest(res);
    const player_id_str = (try req.query()).get("player_id") orelse return badRequest(res);
    const player_id = std.fmt.parseInt(ids.PlayerId, player_id_str, 10) catch return badRequest(res);

    if (!deps.room_manager.isPlayerAllowed(room_id, player_id)) {
        res.status = 403;
        return;
    }
    try upgrade(deps, req, res, player_id, .{ .room = room_id });
}

fn upgrade(deps: *Deps, req: *httpz.Request, res: *httpz.Response, player_id: ids.PlayerId, kind: context.ConnKind) !void {
    const ctx = try deps.allocator.create(context.Context);
    ctx.* = .{
        .player_id = player_id,
        .conn_id = deps.conn_id_gen.next(),
        .kind = kind,
        .lobby = deps.lobby,
        .room_manager = deps.room_manager,
        .allocator = deps.allocator,
    };
    if (try httpz.upgradeWebsocket(player_conn.PlayerConn, req, res, ctx) == false) {
        deps.allocator.destroy(ctx);
        badRequest(res);
    }
}

fn badRequest(res: *httpz.Response) void {
    res.status = 400;
    res.body = "invalid websocket request";
}
