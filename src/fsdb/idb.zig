const std = @import("std");
const IDb = @This();
const OffsetReader = @import("./offset_reader.zig");

pub const EntryKind = enum {
    dir,
    file,
};
pub const Entry = struct {
    kind: EntryKind = .file,
    basename: []const u8,
    size: u64 = 0,
};

// pub const Dir = struct {
//     db: IDb,
//     const Self = @This();
//     pub fn childIterator(self: *Self) EntryIterator {
//         return .{ .db = self.db };
//     }
// };

pub const EntryFile = struct {
    offsetReader: OffsetReader,

    const Self = @This();

    pub fn readAt(self: Self, buf: []u8, offset: u64) usize {
        return self.offsetReader.readAt(buf, offset);
    }
};

pub const DirIterator = struct {
    db: IDb,
    index: u64 = 0,

    const Self = @This();

    pub fn next(self: *Self) ?Entry {
        //         std.log.warn("next |{d}| path|{s}|", .{ self.index, self.path });

        const i = self.index;
        self.index += 1;
        return self.db.getAt(i);
    }
};

pub const DbContext = struct { db: IDb, path: []const u8 };

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    get: *const fn (ptr: *anyopaque, path: []const u8) ?Entry,
    getAt: *const fn (ptr: *anyopaque, at: u64) ?Entry,
    getDirIterator: *const fn (ptr: *anyopaque, path: []const u8) error{DirNotFound}!DirIterator,
    openFile: *const fn (ptr: *anyopaque, path: []const u8) ?EntryFile,

    // getAt: *const fn (ptr: *anyopaque, path: []const u8, at: usize) ?Entry,
    // readAt: *const fn (ptr: *anyopaque, path: []const u8, buf: []u8, at: usize) u64,
    // dbCtx: ?*const fn (ptr: *anyopaque, path: []const u8) ?DbContext = null,
    // childIteratorAt: *const fn (ptr: *anyopaque, path: []const u8, at: usize) EntryIterator,
    // reader: *const fn (ptr: *anyopaque, path: []const u8) Entry.Reader,
};

pub fn unwrap(self: IDb, comptime T: type) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), self.ptr));
}

pub fn get(self: IDb, path: []const u8) ?Entry {
    return self.vtable.get(self.ptr, path);
}

pub fn getDirIterator(self: *IDb, path: []const u8) !DirIterator {
    return self.vtable.getDirIterator(self.ptr, path);
}

pub fn getAt(self: IDb, at: u64) ?Entry {
    return self.vtable.getAt(self.ptr, at);
}

pub fn openFile(self: IDb, path: []const u8) ?EntryFile {
    return self.vtable.openFile(self.ptr, path);
}

// pub fn readAt(self: IDb, path: []const u8, buf: []u8, at: usize) u64 {
//     return self.vtable.getAt(self.ptr, path, buf, at);
// }

// pub fn dbCtx(self: IDb, path: []const u8) ?DbContext {
//     if (self.vtable.dbCtx) |vDbCtx| {
//         return vDbCtx(self.ptr, path);
//     }
//     return .{ .db = self, .path = path };
// }

// pub fn reader(self: IDb, path: []const u8) ?EntryReader {
//     if (self.vtable.dbCtx) |vDbCtx| {
//         if (vDbCtx(self.ptr, path)) |ctx| {
//             return .{ .db = ctx.db, .path = ctx.path };
//         }
//     }

//     return null;
// }

// pub fn childIterator(self: IDb, path: []const u8) EntryIterator {
//     if (self.vtable.dbCtx) |vDbCtx| {
//         if (vDbCtx(self.ptr, path)) |ctx| {
//             return .{ .db = ctx.db, .path = ctx.path, .index = 0 };
//         }
//     }

//     return .{ .db = self, .path = path, .index = 0 };
// }
