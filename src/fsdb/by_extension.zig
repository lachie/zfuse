const std = @import("std");
const Db = @import("./idb.zig");
const splitPath = @import("./split_path.zig").splitPath;

pub const ByExtensionDb = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    extensions: ExtMap,

    const Entry = Db.Entry;
    const EntryMap = std.array_hash_map.StringArrayHashMap(Entry);
    const ExtMap = std.array_hash_map.StringArrayHashMap(EntryMap);
    const Self = @This();

    pub fn idb(self: *Self) Db {
        return .{ .ptr = self, .vtable = &.{
            .get = get,
            .getAt = getAt,
        } };
    }

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Self {
        return .{
            .allocator = allocator,
            .source = source,
            .extensions = ExtMap.init(allocator),
        };
    }
    pub fn deinit(self: *Self) void {
        for (self.extensions.values()) |*ext| {
            for (ext.values()) |*entry| {
                self.allocator.free(entry.basename);
            }
            ext.deinit();
        }
        for (self.extensions.keys()) |key| {
            self.allocator.free(key);
        }
        self.extensions.deinit();
    }

    pub fn indexSource(self: *Self) !void {
        var dir = try std.fs.cwd().openIterableDir(self.source, .{});
        defer dir.close();

        var iter = try dir.walk(self.allocator);
        defer iter.deinit();

        while (try iter.next()) |e| {
            if (e.kind == .File) {
                const rawExt = std.fs.path.extension(e.basename);
                var ext: []const u8 = undefined;
                if (rawExt.len == 0) {
                    ext = "";
                } else {
                    ext = try self.allocator.dupe(u8, rawExt[1..]);
                }

                var extEntry = try self.extensions.getOrPut(ext);
                if (!extEntry.found_existing) {
                    extEntry.value_ptr.* = EntryMap.init(self.allocator);
                } else {
                    self.allocator.free(ext);
                }

                std.log.warn("e: {s} {d}", .{ e.basename, e.basename.len });

                const basename = try self.allocator.dupe(u8, e.basename);

                try extEntry.value_ptr.put(basename, Entry{
                    .kind = .file,
                    .basename = basename,
                });
            }
        }
    }

    fn get(ptr: *anyopaque, path: []const u8) ?*const Db.Entry {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        const hr = splitPath(path);
        std.log.warn("get {s} hr {any}", .{ path, hr });
        if (self.extensions.get(hr.head)) |ext| {
            if (hr.rest.len == 0) {
                return &Entry{
                    .basename = hr.head,
                    .kind = .dir,
                };
            }

            std.log.warn("key: {s}", .{ext.keys()[0]});
            return ext.getPtr(hr.rest);
        }
        return null;
    }

    fn getAt(self: *Self, path: []const u8, at: usize) ?*const Entry {}

    fn dbCtx(ptr: *anyopaque, path: []const u8) Db.DbContext {
        const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        return .{ .db = self.idb(), .path = path };
    }
};

test "ByExtensionDb" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile("file.txt", "nonsense");
    try tmp.dir.makeDir("subdir");

    const p = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(p);

    std.log.warn("tmpdir {s}", .{p});

    var db = ByExtensionDb.init(testing.allocator, p);
    defer db.deinit();

    try db.indexSource();

    std.log.warn("db {any}", .{db});

    const idb = db.idb();

    {
        const e = idb.get("/txt");
        // std.log.warn("txt e {any}", .{e});
        try testing.expect(e != null);
        try testing.expectEqualStrings("txt", e.?.basename);
    }
    {
        const e = idb.get("/nothing");
        try testing.expect(e == null);
    }
    {
        const e = idb.get("/txt/file.txt");
        try testing.expectEqualStrings("file.txt", e.?.basename);
    }
    {
        const e = idb.get("/txt/nothing.txt");
        try testing.expect(e == null);
    }
}
