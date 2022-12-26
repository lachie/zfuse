const std = @import("std");
const mem = std.mem;
const Source = @import("./source.zig").Source;

// const log = std.log.scoped(.db);

// const Entry = union(enum) {
//     dir: Dir,
// };

var null_allocator = std.heap.FixedBufferAllocator.init("");

pub const EntryType = enum {
    dir,
    file,
};
pub const StringEntry = struct {
    allocator: mem.Allocator = undefined,
    type: EntryType,
    path: []const u8,
    basename: [:0]const u8,
    content: []u8 = "",

    const Self = @This();

    pub fn initWithString(allocator: mem.Allocator, inPath: []const u8, inContent: []const u8) !Self {
        const path = try allocator.dupe(u8, inPath);

        // basenameZ setup
        // alloc separate memory of the basename with a sentinel to ease working with the FUSE functions.
        const basename = std.fs.path.basename(path);
        const basenameZ = try allocator.dupeZ(u8, basename);

        var content = try allocator.dupe(u8, inContent);

        return .{ .allocator = allocator, .path = path, .basename = basenameZ, .type = .file, .content = content };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(&self.path);
        self.allocator.destroy(&self.basename);
        self.allocator.destroy(&self.content);
    }

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

    pub fn write(self: *Self, buf: []const u8, offset: u64) !usize {
        const newLen = buf.len + offset;
        const usOffset = @intCast(usize, offset);
        if (newLen > self.content.len) {
            self.content = try self.allocator.realloc(self.content, newLen);
        }
        mem.copy(u8, self.content[usOffset..], buf);
        return buf.len;
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
        var iter = self.map.valueIterator();
        while (iter.next()) |e| {
            e.deinit();
        }
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
        .allocator = null_allocator.allocator(),
    };

    pub fn get(self: Self, path: []const u8) ?*const Entry {
        if (mem.eql(u8, "/", path)) {
            return &RootEntry;
        }
        return self.map.getPtr(path);
    }
    pub fn getMut(self: Self, path: []const u8) ?*Entry {
        if (mem.eql(u8, "/", path)) {
            return null;
        }
        return self.map.getPtr(path);
    }

    pub fn del(self: *Self, path: []const u8) bool {
        if (mem.eql(u8, "/", path)) {
            return false;
        }
        if (self.map.fetchRemove(path)) |*map_entry| {
            var entry = map_entry.value;
            entry.deinit();
            return true;
        }
        return false;
    }

    const PrefixIterator = struct {
        parent: *const Entry,
        valueIterator: Map.ValueIterator,

        const plog = std.log.scoped(.PrefixIterator);

        pub fn next(self: *@This()) ?*Entry {
            while (self.valueIterator.next()) |e| {
                if (self.parent.path.len < e.path.len) {
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
        const entry = try Entry.initWithString(self.allocator, path, content);
        return try self.map.put(entry.path, entry);

        // const path = try self.allocator.dupe(u8, inPath);
        // var content = try self.allocator.dupe(u8, inContent);
        // return try self.map.put(path, .{ .path = path, .basename = std.fs.path.basename(path), .type = .file, .content = content });
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
