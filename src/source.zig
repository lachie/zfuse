const std = @import("std");

pub const Source = struct {
    allocator: std.mem.Allocator,
    idir: std.fs.IterableDir,
    walker: std.fs.IterableDir.Walker,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, idir: std.fs.IterableDir) !Self {
        const walker = try idir.walk(allocator);
        return Self{ .allocator = allocator, .idir = idir, .walker = walker };
    }

    pub fn deinit(self: *Self) void {
        self.walker.deinit();
    }
};

pub fn sourceAt(allocator: std.mem.Allocator, path: []const u8) !Source {
    const dir = try std.fs.cwd().openIterableDir(path, .{});
    return Source.init(allocator, dir);
}
