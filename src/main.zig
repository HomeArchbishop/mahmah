const std = @import("std");
const httpz = @import("httpz");
const ids = @import("shared/ids.zig");
const routes = @import("net/routes.zig");
const Lobby = @import("lobby/lobby.zig").Lobby;
const RoomManager = @import("room/room_manager.zig").RoomManager;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var player_id_gen = ids.PlayerIdGen{};
    var conn_id_gen = ids.ConnIdGen{};
    var room_id_gen = ids.RoomIdGen{};

    var room_manager = RoomManager.init(allocator, init.io);
    defer room_manager.deinit();
    try room_manager.startTimer();

    var lobby = Lobby.init(allocator, &room_manager, &room_id_gen, &player_id_gen);
    defer lobby.deinit();

    var deps = routes.Deps{
        .allocator = allocator,
        .player_id_gen = &player_id_gen,
        .conn_id_gen = &conn_id_gen,
        .lobby = &lobby,
        .room_manager = &room_manager,
    };

    var server = try httpz.Server(*routes.Deps).init(init.io, allocator, .{
        .address = .localhost(8080),
    }, &deps);
    defer {
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.get("/ws/lobby", routes.wsLobby, .{});
    router.get("/ws/room/:room_id", routes.wsRoom, .{});

    std.debug.print("listening on http://localhost:8080\n", .{});
    try server.listen();
}
