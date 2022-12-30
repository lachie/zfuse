const std = @import("std");
const mem = std.mem;
const Db = @import("./idb.zig");
const Entry = Db.Entry;
const splitPath = @import("./split_path.zig").splitPath;

// const Entry = struct {
// The type erased pointer to the allocator implementation
// ptr: *anyopaque,
// vtable: *const VTable,

// pub const VTable = struct {
//     read: *const fn (ctx: *anyopaque, buf: []u8) usize,
// };

// pub fn read() usize {}
// pub fn path() []const u8 {}
// pub fn basename() []const u8 {}
// pub fn metadata() void {}
// pub fn isDir() bool {}
// };

const EntryIterator = struct {};

// pub const Db = struct {
//     const Self = @This();
//     pub fn get() ?*const Entry {
//         return null;
//     }
//     pub fn getChildrenAt(self: *Self, parent: *const Entry, at: usize, len: usize) EntryIterator {
//         _ = self;
//         _ = parent;
//         _ = at;
//         _ = len;
//         return .{};
//     }
// };

pub const MetaDb = struct {
    const DbMap = std.hash_map.StringHashMap(Db);
    const DbEntryMap = std.array_hash_map.StringArrayHashMap(Entry);
    // const DbNameList = std.ArrayList([:0]u8);
    const Self = @This();

    dbs: DbMap,
    dbEntries: DbEntryMap,
    // dbNames: DbNameList,

    pub fn idb(self: *Self) Db {
        return .{ .ptr = self, .vtable = &.{
            .get = get,
            .getAt = getAt,
            .dbCtx = dbCtx,
        } };
    }

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .dbs = DbMap.init(allocator),
            .dbEntries = DbEntryMap.init(allocator),
            // .dbNames = DbNameList.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        std.log.warn("meta db deinit", .{});
        self.dbs.deinit();
        for (self.dbEntries.values()) |entry| {
            self.dbEntries.allocator.free(entry.basename);
        }
        self.dbEntries.deinit();
    }

    pub fn mount(self: *Self, name: []const u8, db: Db) !void {
        const basename = try self.dbEntries.allocator.dupeZ(u8, name);
        try self.dbs.put(basename, db);

        const entry = Entry{ .basename = basename, .kind = .dir };
        try self.dbEntries.put(name, entry);
    }

    pub fn mounted(self: Self, name: []const u8) ?Db {
        return self.dbs.get(name);
    }

    fn get(ptr: *anyopaque, path: []const u8) ?Entry {
        const hr = splitPath(path);
        std.log.warn("metaDb get {any}", .{hr});

        if (hr.root) {
            return Entry{
                .basename = "",
                .kind = .dir,
            };
        }

        if (dbCtx(ptr, path)) |ctx| {
            std.log.warn("   |{s}| sub-path |{s}|", .{ hr.head, ctx.path });

            // return an Entry representing the sub-db as a dir
            if (ctx.path.len != 0) {
                std.log.warn("   getting inner {s}", .{ctx.path});
                return ctx.db.get(ctx.path);
            }
        }

        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        std.log.warn("   getting dbe {s}", .{hr.head});
        if (self.dbEntries.get(hr.head)) |entry| {
            std.log.warn("   entry: {*} {s}", .{ entry.basename, entry.basename });
            return entry;
        }

        return null;

        // const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        // const sPath = splitPath(path);
        // if (sPath.head.len == 0) {
        //     return &Entry{
        //         .basename = "",
        //         .kind = .dir,
        //     };
        // }
        // if (self.dbs.get(sPath.head)) |db| {
        //     if (sPath.rest.len == 0) {
        //         const entry = self.dbEntries.get(sPath.head).?;
        //         return &entry;
        //     } else {
        //         return db.get(sPath.rest);
        //     }
        // }

        // return null;
    }

    fn getAt(ptr: *anyopaque, path: []const u8, at: usize) ?Entry {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        const hr = splitPath(path);
        std.log.warn("getat {any} {d}", .{ hr, at });

        if (hr.root) {
            const values = self.dbEntries.values();
            if (at < values.len) {
                return values[at];
            }
            return null;
        }

        if (dbCtx(ptr, path)) |ctx| {
            std.log.warn("   |{s}| sub-path |{s}|", .{ hr.head, ctx.path });
            return ctx.db.getAt(ctx.path, at);

            // return an Entry representing the sub-db as a dir
            // if (ctx.path.len != 0) {
            //     std.log.warn("   getting inner {s}", .{ctx.path});
            //     return ctx.db.getAt(ctx.path, at);
            // }
        }

        // _ = ptr;
        // _ = path;
        // _ = at;
        // const hr = splitPath(path);
        // if (hr.head.len == 0) {
        //     return .{};
        // }
        // const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));

        // if (hr.rest.len == 0) {}

        // if (self.dbs.get(hr.head)) |db| {
        //     return db.childIteratorAt(hr.rest, at);
        // }
        return null;
    }

    fn dbCtx(ptr: *anyopaque, path: []const u8) ?Db.DbContext {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        const hr = splitPath(path);

        // if (hr.root) {
        //     return Db.DbContext{ .db = self.idb(), .path = path };
        // }

        // if (hr.head.len > 0) {
        if (self.dbs.get(hr.head)) |db| {
            return db.dbCtx(hr.rest);
        }

        // return .{ .db = self.idb(), .path = hr.rest };
        // }

        return null;
    }
};

const TestDb = struct {
    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn idb(self: *Self) Db {
        return .{
            .ptr = self,
            .vtable = &.{
                .get = get,
                .getAt = getAt,
                // .dbCtx = dbCtx,
            },
        };
    }

    fn get(ptr: *anyopaque, path: []const u8) ?Entry {
        const hr = splitPath(path);
        std.log.warn("test db get {any}", .{hr});

        if (std.mem.eql(u8, "null", hr.head)) {
            return null;
        }
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        const basename = std.fmt.allocPrintZ(self.allocator, "p:{s}", .{hr.head}) catch return null;
        return .{ .basename = basename };
    }

    fn getAt(ptr: *anyopaque, path: []const u8, at: usize) ?Entry {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        const basename = std.fmt.allocPrintZ(self.allocator, "p:{s}:{d}", .{ path, at }) catch return null;
        return .{ .basename = basename };
    }

    // fn dbCtx(ptr: *anyopaque, path: []const u8) ?Db.DbContext {
    //     const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
    //     return .{ .db = self.idb(), .path = path };
    // }
};

test "MetaDb.get" {
    const testing = std.testing;
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var mdb = MetaDb.init(allocator);
    defer mdb.deinit();
    var db = TestDb{ .allocator = arena.allocator() };

    try mdb.mount("tester", db.idb());

    var imdb = mdb.idb();

    {
        const e = imdb.get("/tester/y").?;

        // testing.expect(e != null);
        try testing.expectEqualSlices(u8, "p:y", e.basename);
    }
    {
        const e = imdb.get("/tester/null");
        try testing.expect(e == null);
    }
    {
        const e = imdb.get("/huh/whay");
        try testing.expect(e == null);
    }
    {
        const e = imdb.get("/tester").?;
        std.log.warn("e {s} {d}", .{ e.basename, e.basename.len });
        try testing.expectEqualStrings("tester", e.basename);
    }
}

test "MetaDb.getAt" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var mdb = MetaDb.init(allocator);
    defer mdb.deinit();

    var db = TestDb{ .allocator = allocator };

    try mdb.mount("t0", db.idb());
    try mdb.mount("t1", db.idb());

    var imdb = mdb.idb();

    {
        const e = imdb.getAt("/", 0).?;
        try testing.expectEqualSlices(u8, "t0", e.basename);
    }
    {
        const e = imdb.getAt("/", 1).?;
        try testing.expectEqualSlices(u8, "t1", e.basename);
    }
    {
        const e = imdb.getAt("/", 2);
        try testing.expect(e == null);
    }
    {
        const e = imdb.getAt("/t0", 5).?;
        std.log.warn("e {s} {d}", .{ e.basename, e.basename.len });
        try testing.expectEqualSlices(u8, "p::5", e.basename);
    }
}
