const ids = @import("../shared/ids.zig");

pub const CAPACITY: usize = 4;

pub const Error = error{
    Forbidden,
    Conflict,
    Full,
    NotBot,
    NotReady,
    AlreadyStarted,
};

/// Lobby waiting table. Not the in-game Room.
pub const Table = struct {
    id: ids.RoomId,
    host_id: ids.PlayerId,
    started: bool = false,
    seats: [CAPACITY]?ids.PlayerId = .{null} ** CAPACITY,
    occupied: u8 = 0,

    pub fn init(id: ids.RoomId, host_id: ids.PlayerId) Table {
        var table: Table = .{
            .id = id,
            .host_id = host_id,
        };
        table.seats[0] = host_id;
        table.occupied = 1;
        return table;
    }

    pub fn contains(self: *const Table, player_id: ids.PlayerId) bool {
        for (self.seats) |seat| {
            if (seat == player_id) return true;
        }
        return false;
    }

    pub fn isHost(self: *const Table, player_id: ids.PlayerId) bool {
        return self.host_id == player_id;
    }

    pub fn join(self: *Table, player_id: ids.PlayerId) Error!void {
        if (self.started) return error.AlreadyStarted;
        if (ids.isBot(player_id)) return error.Forbidden;
        if (self.contains(player_id)) return error.Conflict;
        if (self.occupied >= CAPACITY) return error.Full;
        self.seats[self.occupied] = player_id;
        self.occupied += 1;
    }

    pub fn addBot(self: *Table, host_id: ids.PlayerId, bot_id: ids.PlayerId) Error!void {
        if (!self.isHost(host_id)) return error.Forbidden;
        if (self.started) return error.AlreadyStarted;
        if (!ids.isBot(bot_id)) return error.NotBot;
        if (self.occupied >= CAPACITY) return error.Full;
        self.seats[self.occupied] = bot_id;
        self.occupied += 1;
    }

    pub fn removeBot(self: *Table, host_id: ids.PlayerId, bot_id: ids.PlayerId) Error!void {
        if (!self.isHost(host_id)) return error.Forbidden;
        if (self.started) return error.AlreadyStarted;
        if (!ids.isBot(bot_id)) return error.NotBot;
        if (!self.contains(bot_id)) return error.Conflict;
        self.removeSeat(bot_id);
    }

    pub fn markStarted(self: *Table, host_id: ids.PlayerId) Error!void {
        if (!self.isHost(host_id)) return error.Forbidden;
        if (self.started) return error.AlreadyStarted;
        if (self.occupied != CAPACITY) return error.NotReady;
        self.started = true;
    }

    pub fn leave(self: *Table, player_id: ids.PlayerId) void {
        if (self.started) return;
        if (!self.contains(player_id)) return;
        self.removeSeat(player_id);
        if (self.host_id == player_id) {
            self.host_id = self.firstHuman() orelse 0;
        }
    }

    pub fn hasHumans(self: *const Table) bool {
        return self.firstHuman() != null;
    }

    pub fn copyMembers(self: *const Table, out: *[CAPACITY]ids.PlayerId) []const ids.PlayerId {
        var n: usize = 0;
        for (self.seats) |seat| {
            if (seat) |player_id| {
                out[n] = player_id;
                n += 1;
            }
        }
        return out[0..n];
    }

    fn firstHuman(self: *const Table) ?ids.PlayerId {
        for (self.seats) |seat| {
            if (seat) |player_id| {
                if (!ids.isBot(player_id)) return player_id;
            }
        }
        return null;
    }

    fn removeSeat(self: *Table, player_id: ids.PlayerId) void {
        var i: usize = 0;
        while (i < self.occupied) : (i += 1) {
            if (self.seats[i] == player_id) {
                var j = i;
                while (j + 1 < self.occupied) : (j += 1) {
                    self.seats[j] = self.seats[j + 1];
                }
                self.occupied -= 1;
                self.seats[self.occupied] = null;
                return;
            }
        }
    }
};
