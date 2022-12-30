const std = @import("std");
const Db = @import("./idb.zig");
const splitPath = @import("./split_path.zig").splitPath;

pub const DirDb = struct {
    allocator: std.mem.Allocator,
    entries: Db,
    dirs: DirMap,

    const DirMap = std.array_hash_map.StringArrayHashMap(Db);

    const Self = @This();
    pub fn idb(self: *Self) Db {
        return .{
            .ptr = self,
            .vtable = &.{
                .get = get,
                .getDir = getDir,
                .getAt = getAt,
            },
        };
    }

    pub fn init(allocator: std.mem.Allocator, entries: Db) Self {
        return .{
            .allocator = allocator,
            .entries = entries,
            .dirs = DirMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.dirs.deinit();
    }

    fn get(ptr: *anyopaque, path: []const u8) ?Db.Entry {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        const hr = splitPath(path);

        std.log.warn("dir get {any}", .{hr});
        if (hr.root) {
            return Db.Entry{
                .basename = hr.head,
                .kind = .dir,
            };
        }

        if (hr.leaf) {
            if (self.dirs.contains(hr.head)) {
                return .{
                    .kind = .dir,
                    .basename = hr.head,
                };
            }
            return self.entries.get(path);
        }

        if (self.dirs.get(hr.head)) |dir| {
            return dir.get(hr.rest);
        }

        return null;
    }

    fn getDir(ptr: *anyopaque, path: []const u8) ?*Db.Dir {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        const hr = splitPath(path);

        if (hr.root) {
            return &Db.Dir{};
        }

        if (self.dirs.get(hr.head)) |dir| {
            return dir.getDir(hr.rest);
        }

        return null;
    }

    fn getAt(ptr: *anyopaque, at: u64) ?Db.Entry {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));

        const dirs = self.dirs.values();
        if (at < dirs.len) {
            const key = self.dirs.keys()[at];
            return .{
                .kind = .dir,
                .basename = key,
            };
        }

        return self.entries.getAt(at - dirs.len);
    }
};

test "DirDb" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var nullDb = @import("./null.zig").nullDb;
    const FlatDb = @import("./flat.zig").FlatDb;

    var ddb = DirDb.init(arena.allocator(), nullDb.idb());
    defer ddb.deinit();

    var flat = FlatDb.init(arena.allocator());
    defer flat.deinit();

    try flat.add("hello.txt", 14);

    var ddbSub1 = DirDb.init(arena.allocator(), flat.idb());
    defer ddbSub1.deinit();

    try ddb.dirs.put("sub1", ddbSub1.idb());

    var idb = ddb.idb();

    const testing = std.testing;

    {
        const e = idb.get("nope.txt");
        try testing.expect(e == null);
    }
    {
        const e = idb.get("sub1").?;
        try testing.expectEqualStrings("sub1", e.basename);
    }
    {
        const d = idb.getDir("");
        try testing.expect(d != null);
    }
    {
        const d = idb.getDir("sub1");
        try testing.expect(d != null);
    }
    {
        const e = idb.get("sub1/hello.txt").?;
        try testing.expectEqualStrings("hello.txt", e.basename);
    }
    // {
    //     const e = idb.getAt(0).?;
    //     try testing.expectEqualStrings("hello.txt", e.basename);
    // }
}
