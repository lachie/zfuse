const std = @import("std");
const mem = std.mem;
const Source = @import("./source.zig").Source;

// const log = std.log.scoped(.db);

// const Entry = union(enum) {
//     dir: Dir,
// };

pub const Db = struct {
    allocator: std.mem.Allocator,
    map: Map,
    source: Source,

    const Map = std.hash_map.StringHashMap(Entry);

    const Self = @This();
    pub const EntryType = enum {
        dir,
        file,
    };
    pub const Entry = struct {
        type: EntryType,
        path: []const u8,
        basename: []const u8,
        content: []u8 = "",
    };

    pub fn init(allocator: std.mem.Allocator, source: Source) !Self {
        const map = Map.init(allocator);
        return Self{ .allocator = allocator, .source = source, .map = map };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.source.deinit();
    }

    const RootEntry = Entry{
        .path = "/",
        .basename = "",
        .type = .dir,
    };

    pub fn get(self: Self, path: []const u8) ?*const Entry {
        if (mem.eql(u8, "/", path)) {
            return &RootEntry;
        }
        return self.map.getPtr(path);
    }

    const PrefixIterator = struct {
        parent: *const Entry,
        valueIterator: Map.ValueIterator,

        const log = std.log.scoped(.PrefixIterator);

        pub fn next(self: *@This()) ?*Entry {
            log.debug("next {s}", .{self.parent.path});
            while (self.valueIterator.next()) |e| {
                log.debug("   entry {s}", .{e.path});
                if (self.parent.path.len < e.path.len) {
                    log.debug("   chk hay {s} ndl {s}", .{ e.path, self.parent.path });
                    if (mem.startsWith(u8, e.path, self.parent.path)) {
                        return e;
                    }
                }
            }
            return null;
        }
    };

    pub fn getChildren(self: *Self, parent: *const Entry) PrefixIterator {
        return PrefixIterator{ .valueIterator = self.map.valueIterator(), .parent = parent };
    }

    pub fn putString(self: *Self, path: []const u8, content: []const u8) !void {
        var cnt = try self.allocator.dupe(u8, content);
        return try self.map.put(path, .{ .path = path, .basename = std.fs.path.basename(path), .type = .file, .content = cnt });
    }
    pub fn mknod(self: *Self, path: []const u8) !void {
        return try self.map.put(path, .{ .path = path, .basename = std.fs.path.basename(path), .type = .file });
    }
};

pub fn dbSource(allocator: std.mem.Allocator, path: []const u8) !Db {
    const dir = try std.fs.cwd().openIterableDir(path, .{});
    const source = try Source.init(allocator, dir);
    return Db.init(allocator, source);
}
