const std = @import("std");
const IDb = @This();

pub const EntryKind = enum {
    dir,
    file,
};
pub const Entry = struct {
    kind: EntryKind = .file,
    basename: []const u8,
};

pub const EntryIterator = struct {
    db: *IDb,
    path: []const u8,
    index: usize,

    const Self = @This();

    pub fn next(self: *Self) ?*const Entry {
        const i = self.index;
        self.index += 1;
        return self.db.getAt(self.path, i);
    }
};

pub const DbContext = struct { db: IDb, path: []const u8 };

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    get: *const fn (ptr: *anyopaque, path: []const u8) ?*const Entry,
    getAt: *const fn (ptr: *anyopaque, path: []const u8, at: usize) ?*const Entry,
    dbCtx: ?*const fn (ptr: *anyopaque, path: []const u8) ?DbContext = null,
    // childIteratorAt: *const fn (ptr: *anyopaque, path: []const u8, at: usize) EntryIterator,
    // reader: *const fn (ptr: *anyopaque, path: []const u8) Entry.Reader,
};

pub fn get(self: IDb, path: []const u8) ?*const Entry {
    return self.vtable.get(self.ptr, path);
}
pub fn getAt(self: IDb, path: []const u8, at: usize) ?*const Entry {
    return self.vtable.getAt(self.ptr, path, at);
}

pub fn dbCtx(self: IDb, path: []const u8) ?DbContext {
    if (self.vtable.dbCtx) |vDbCtx| {
        return vDbCtx(self.ptr, path);
    }
    return .{ .db = self, .path = path };
}

pub fn childIterator(self: *IDb, path: []const u8) ?EntryIterator {
    if (self.vtable.dbCtx(self.ptr, path)) |ctx| {
        return .{ .db = ctx.db, .path = ctx.path, .index = 0 };
    }

    return null;
}
