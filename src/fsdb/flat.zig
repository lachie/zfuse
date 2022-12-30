const std = @import("std");
const Db = @import("./idb.zig");
const splitPath = @import("./split_path.zig").splitPath;

pub fn FlatDb(comptime Content: anytype) type {
    return struct {
        allocator: std.mem.Allocator,
        entries: EntryMap,
        content: ContentMap,

        const Self = @This();
        const Entry = Db.Entry;
        const EntryMap = std.array_hash_map.StringArrayHashMap(Entry);
        const ContentMap = std.array_hash_map.StringArrayHashMap(Content);

        pub fn idb(self: *Self) Db {
            return .{ .ptr = self, .vtable = &.{
                .get = get,
                .getAt = getAt,
                .getDirIterator = getDirIterator,
                .openFile = openFile,
            } };
        }

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .entries = EntryMap.init(allocator),
                .content = ContentMap.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            std.log.warn("flat db deinit", .{});
            for (self.entries.values()) |*entry| {
                self.allocator.free(entry.basename);
            }
            self.entries.deinit();
            self.content.deinit();
        }

        pub fn add(self: *Self, basenameIn: []const u8, content: Content) !void {
            const basename = try self.allocator.dupeZ(u8, basenameIn);
            std.log.warn("flat db add {s}", .{basename});

            try self.entries.put(basename, Entry{
                .basename = basename,
                .size = content.size(),
                .kind = .file,
            });
            try self.content.put(basename, content);
        }

        fn get(ptr: *anyopaque, path: []const u8) ?Db.Entry {
            const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
            const hr = splitPath(path);

            if (hr.root) {
                return Db.Entry{
                    .basename = hr.head,
                    .kind = .dir,
                };
            }

            return self.entries.get(hr.head);
        }

        fn getDirIterator(ptr: *anyopaque, path: []const u8) !Db.DirIterator {
            var self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
            _ = path;

            return Db.DirIterator{ .db = self.idb() };
        }

        fn getAt(ptr: *anyopaque, at: u64) ?Entry {
            const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));

            const values = self.entries.values();
            if (at < values.len) {
                return values[at];
            }
            return null;
        }

        pub fn openFile(ptr: *anyopaque, path: []const u8) ?Db.EntryFile {
            var self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));

            if (self.content.getPtr(path)) |content| {
                return Db.EntryFile{
                    .offsetReader = content.offsetReader(),
                };
            }

            return null;
        }

        // fn getAt(ptr: *anyopaque, path: []const u8, at: usize) ?Entry {
        //     _ = path;
        //     const self = @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));

        //     const values = self.entries.values();
        //     std.log.warn("   flat get at {d} {any}", .{ at, values });
        //     if (at < values.len) {
        //         return values[at];
        //     }
        //     return null;
        // }
    };
}

test "FlatDb get" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    const C = @import("./fixed_buffer_content.zig").FixedBufferContent;

    var db = FlatDb(C).init(allocator);
    defer db.deinit();

    // const c1 = try allocator.create(C);
    // const c2 = try allocator.create(C);
    var c1 = C.init("howdy");
    var c2 = C.init("doody");

    try db.add("hello.txt", c1);
    try db.add("cats.gif", c2);

    var idb = db.idb();

    {
        const e = idb.get("hello.txt").?;
        try testing.expectEqualSlices(u8, "hello.txt", e.basename);
    }
    {
        const e = idb.get("hello.txt/deeper").?;
        try testing.expectEqualSlices(u8, "hello.txt", e.basename);
    }
    {
        const e = idb.get("").?;
        try testing.expectEqualSlices(u8, "", e.basename);
    }
    {
        const e = idb.get("nope.txt");
        try testing.expect(e == null);
    }
    // {
    //     const d = idb.getDir("");
    //     try testing.expect(d == null);
    // }
    // {
    //     const d = idb.getDir("hello.txt");
    //     try testing.expect(d == null);
    // }
    {
        const e = idb.getAt(0).?;
        try testing.expectEqualSlices(u8, "hello.txt", e.basename);
    }
    {
        const e = idb.getAt(1).?;
        try testing.expectEqualSlices(u8, "cats.gif", e.basename);
    }
    {
        const e = idb.getAt(2);
        try testing.expect(e == null);
    }
    // {
    //     const e = idb.getAt("/dunno", 1).?;
    //     try testing.expectEqualSlices(u8, "cats.gif", e.basename);
    // }
    {
        var f = idb.openFile("hello.txt").?;
        var buf = [_]u8{0} ** 10;
        {
            const read = f.offsetReader.readAt(&buf, 0);
            try testing.expectEqualStrings("howdy", buf[0..read]);
            try testing.expectEqual(read, 5);
            std.log.warn("read: {d} {s}", .{ read, buf });
        }
        {
            const read = f.offsetReader.readAt(&buf, 2);
            try testing.expectEqualStrings("wdy", buf[0..read]);
            try testing.expectEqual(read, 3);
            std.log.warn("read: {d} {s}", .{ read, buf[0..read] });
        }

        // try testing.expectEqualSlices(u8, "hello.txt", e.basename);
    }
}
