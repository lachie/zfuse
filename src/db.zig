const std = @import("std");
const mem = std.mem;
const Source = @import("./source.zig").Source;

// const log = std.log.scoped(.db);

// const Entry = union(enum) {
//     dir: Dir,
// };

pub const EntryType = enum {
    dir,
    file,
};
pub const StringEntry = struct {
    type: EntryType,
    path: []const u8,
    basename: []const u8,
    content: []u8 = "",

    const Self = @This();

    pub fn len(self: Self) u64 {
        return self.content.len;
    }

    pub fn read(self: Self, buf: []u8, offset: u64) usize {
        if (offset < self.content.len) {
            var end = offset +% buf.len;
            if (end > self.content.len) {
                end = self.content.len -% offset;
            }
            mem.copy(u8, buf, self.content[offset..end]);
            return end - offset;
        } else {
            return 0;
        }
    }
    pub fn write(_: Self, _: []const u8, _: u64) usize {
        return 0;
    }
};

pub const Db = struct {
    allocator: std.mem.Allocator,
    map: Map,
    source: Source,

    const Entry = StringEntry;
    const Map = std.hash_map.StringHashMap(Entry);

    const Self = @This();
    const log = std.log.scoped(.db);

    pub fn init(allocator: std.mem.Allocator, source: Source) !Self {
        const map = Map.init(allocator);
        return Self{ .allocator = allocator, .source = source, .map = map };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.source.deinit();
    }

    pub fn debug(self: *Self) void {
        var iter = self.map.iterator();
        while (iter.next()) |e| {
            const entry = e.value_ptr;
            log.debug("e {s}", .{entry.path});
            log.debug("  {d} {s}", .{ entry.len(), entry.content[0..] });
        }
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

        const plog = std.log.scoped(.PrefixIterator);

        pub fn next(self: *@This()) ?*Entry {
            plog.debug("next {s}", .{self.parent.path});
            while (self.valueIterator.next()) |e| {
                plog.debug("   entry {s}", .{e.path});
                if (self.parent.path.len < e.path.len) {
                    plog.debug("   chk hay {s} ndl {s}", .{ e.path, self.parent.path });
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

    pub fn putString(self: *Self, inPath: []const u8, inContent: []const u8) !void {
        const path = try self.allocator.dupe(u8, inPath);
        var content = try self.allocator.dupe(u8, inContent);
        return try self.map.put(path, .{ .path = path, .basename = std.fs.path.basename(path), .type = .file, .content = content });
    }
    pub fn mknod(self: *Self, path: []const u8) !void {
        return self.putString(path, "");
    }
};

pub fn dbSource(allocator: std.mem.Allocator, path: []const u8) !Db {
    const dir = try std.fs.cwd().openIterableDir(path, .{});
    const source = try Source.init(allocator, dir);
    return Db.init(allocator, source);
}
