const std = @import("std");
const Db = @import("./idb.zig");
const splitPath = @import("./split_path.zig").splitPath;

pub const NullDb = struct {
    pub fn idb(self: *@This()) Db {
        return .{
            .ptr = self,
            .vtable = &.{
                .get = get,
                .getAt = getAt,
                .getDir = getDir,
            },
        };
    }

    fn get(ptr: *anyopaque, path: []const u8) ?Db.Entry {
        _ = ptr;
        _ = path;
        return null;
    }

    fn getAt(ptr: *anyopaque, at: u64) ?Db.Entry {
        _ = ptr;
        _ = at;
        return null;
    }

    fn getDir(ptr: *anyopaque, path: []const u8) ?*Db.Dir {
        _ = ptr;
        _ = path;
        return null;
    }
};

pub const nullDb = NullDb{};
