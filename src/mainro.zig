const std = @import("std");
const mem = std.mem;
const c = @cImport({
    @cDefine("FUSE_USE_VERSION", "31");
    // @cDefine("_FILE_OFFSET_BITS","64");
    @cInclude("fuse.h");
    @cInclude("errno.h");
    @cInclude("fuse_interop.h");
});
const Db = @import("./fsdb/idb.zig");
const DirDb = @import("./fsdb/dir.zig").DirDb;
const FlatDb = @import("./fsdb/flat.zig").FlatDb;
// const indexSourceByExt = @import("./fsdb/by_extension.zig").indexSource;

const log = std.log.scoped(.main);

var db: Db = undefined;

const FileTracker = struct {
    const File = Db.EntryFile;
    const Map = std.array_hash_map.AutoArrayHashMap(u64, File);
    const Self = @This();

    allocator: mem.Allocator,
    // lastId: u64 = 0,
    // files: Map,

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            // .files = Map.init(allocator),
        };
    }

    pub fn add(self: *Self, file: File) !u64 {
        var filePtr = try self.allocator.create(File);
        filePtr.* = file;

        return @intCast(usize, @ptrToInt(filePtr));

        // TODO reuse id
        // self.lastId += 1;
        // try self.files.put(self.lastId, file);
        // return self.lastId;
    }

    pub fn get(self: *Self, id: u64) !*File {
        if (id == 0) {
            return error.NotFound;
        }
        _ = self;
        // _ = id;
        // return null;
        return @intToPtr(*File, @intCast(usize, id));
        // return @as(?File, @intToPtr(*File, @intCast(usize, id)));
        // return self.files.get(id);
    }

    pub fn del(self: *Self, id: u64) !void {
        // _ = self;
        // _ = id;
        if (self.get(id)) |*file| {
            self.allocator.destroy(file);
        } else |_| {
            return error.NotFound;
        }
        // _ = self.files.swapRemove(id);
    }
};
var openFiles: FileTracker = undefined;

const fuse_file_info = struct {
    //** Open flags.     Available in open() and release() */
    flags: c_int,

    //** In case of a write operation indicates if this was caused
    // by a delayed write from the page cache. If so, then the
    // context's pid, uid, and gid fields will not be valid, and
    // the *fh* value may not match the *fh* value that would
    // have been sent with the corresponding individual write
    // requests if write caching had been disabled. */
    writepage: bool,

    // /** Can be filled in by open, to use direct I/O on this file. */
    direct_io: bool,

    // /** Can be filled in by open. It signals the kernel that any
    //     currently cached file data (ie., data that the filesystem
    //     provided the last time the file was open) need not be
    //     invalidated. Has no effect when set in other contexts (in
    //     particular it does nothing when set by opendir()). */
    keep_cache: bool,

    // /** Indicates a flush operation.  Set in flush operation, also
    //     maybe set in highlevel lock operation and lowlevel release
    //     operation. */
    flush: bool,

    // /** Can be filled in by open, to indicate that the file is not
    //     seekable. */
    nonseekable: bool,

    // /* Indicates that flock locks for this file should be
    //    released.  If set, lock_owner shall contain a valid value.
    //    May only be set in ->release(). */
    flock_release: bool,

    // /** Can be filled in by opendir. It signals the kernel to
    //     enable caching of entries returned by readdir().  Has no
    //     effect when set in other contexts (in particular it does
    //     nothing when set by open()). */
    cache_readdir: bool,

    no_flush: bool,

    // /** Padding.  Reserved for future use*/
    padding: u24,
    padding2: u32,

    // /** File handle id.  May be filled in by filesystem in create,
    //  * open, and opendir().  Available in most other file operations on the
    //  * same file handle. */
    fh: u64,

    // /** Lock owner id.  Available in locking operations and flush */
    lock_owner: u64,

    // /** Requested poll events.  Available in ->poll.  Only set on kernels
    //     which support it.  If unsupported, this field is set to zero. */
    poll_events: u32,
};

pub fn hello_init(_: [*c]c.struct_fuse_conn_info, cfg: [*c]c.struct_fuse_config) callconv(.C) ?*anyopaque {
    log.debug("hello_init", .{});

    cfg.*.kernel_cache = 1;
    // cfg.*.nullpath_ok = 1;

    return @intToPtr(?*anyopaque, 0);
}

// fn tryInt() {}

pub fn hello_getattr(arg_path: [*c]const u8, stbuf: [*c]c.struct_stat, _: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    const path: []const u8 = mem.span(arg_path + 1);

    log.debug("hello_getattr '{s}'", .{path});

    if (db.get(path)) |entry| {
        stbuf.* = mem.zeroes(c.struct_stat);

        log.debug("entry {any}", .{entry});
        switch (entry.kind) {
            .dir => {
                stbuf.*.st_mode = c.S_IFDIR | 0o755;
                stbuf.*.st_nlink = 2;
            },
            .file => {
                stbuf.*.st_mode = c.S_IFREG | 0o444;
                stbuf.*.st_nlink = 1;
                stbuf.*.st_size = @intCast(c.off_t, entry.size);
            },
        }
        return 0;
    } else {
        return -c.ENOENT;
    }
}

pub fn hello_readdir(arg_path: [*c]const u8, buf: ?*anyopaque, maybe_filler: c.fuse_fill_dir_t, offset: c.off_t, _: ?*c.struct_fuse_file_info, _: c.enum_fuse_readdir_flags) callconv(.C) c_int {
    if (maybe_filler) |filler| {
        const path = mem.span(arg_path + 1);

        log.debug("hello_readdir {s} {d}", .{ path, offset });

        var dir = db.getDirIterator(path) catch return -c.ENOENT;

        var out_flags: c.fuse_fill_dir_flags = 0;

        if (offset == 0) {
            _ = filler(buf, ".", null, 0, out_flags);
            _ = filler(buf, "..", null, 0, out_flags);
        }

        while (dir.next()) |child| {
            var basename_scratch = std.BoundedArray(u8, 256).init(child.basename.len + 1) catch return -c.EIO;
            std.mem.copy(u8, basename_scratch.slice(), child.basename);
            basename_scratch.set(child.basename.len, 0);

            out_flags = 0;
            log.debug("    readdir {s}", .{child.basename});

            _ = filler(buf, basename_scratch.slice().ptr, null, 0, out_flags);
        }
    }
    return 0;
}

pub fn hello_open(arg_path: [*c]const u8, arg_fi: ?*c.fuse_file_info) callconv(.C) c_int {
    const path = mem.span(arg_path + 1);

    log.debug("hello_open |{s}| {*}", .{ path, arg_fi });

    if (db.openFile(path)) |file| {
        // log.debug("   entry {s}", .{entry.path});
        // workaround cimport demotion
        var fi = @ptrCast(*fuse_file_info, @alignCast(@alignOf(fuse_file_info), arg_fi));
        log.debug("      before fi {*} {any}", .{ fi, fi });

        if (fi.flags & std.os.O.RDONLY != 0) {
            return -c.EACCES;
        }

        const fh = openFiles.add(file) catch return -c.ENOENT;
        c.set_fh(arg_fi, fh);

        log.debug("    fi {any}", .{fi});

        return 0;
    }

    return -c.ENOENT;
}

pub fn hello_read(arg_path: [*c]const u8, arg_buf: [*c]u8, arg_size: usize, arg_offset: c.off_t, arg_fi: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    // _ = arg_path;

    log.debug("hello_read |{s}|", .{arg_path});

    const fh = c.get_fh(arg_fi);

    // const fi = @ptrCast(*fuse_file_info, @alignCast(@alignOf(fuse_file_info), arg_fi));
    if (openFiles.get(fh)) |file| {
        return @intCast(c_int, file.readAt(arg_buf[0..arg_size], @intCast(u64, arg_offset)));
    } else |_| {
        return -c.EBADF;
    }
}

pub fn hello_release(arg_path: [*c]const u8, arg_fi: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    // _ = arg_path;
    log.debug("hello_release |{s}|", .{arg_path});

    const fh = c.get_fh(arg_fi);
    if (fh == 0) {
        return -c.EBADF;
    }

    openFiles.del(fh) catch return -c.EBADF;

    c.set_fh(arg_fi, 0);
    return 0;
}

pub const hello_oper: c.struct_fuse_operations = c.struct_fuse_operations{
    .getattr = hello_getattr,
    .readdir = hello_readdir,
    .init = hello_init,
    .open = hello_open,
    .read = hello_read,
    .release = hello_release,

    .readlink = null,
    .mknod = null,
    .mkdir = null,
    .unlink = null,
    .rmdir = null,
    .symlink = null,
    .rename = null,
    .link = null,
    .chmod = null,
    .chown = null,
    .truncate = null,
    .write = null,
    .statfs = null,
    .flush = null,
    .fsync = null,
    .setxattr = null,
    .getxattr = null,
    .listxattr = null,
    .removexattr = null,
    .opendir = null,
    .releasedir = null,
    .fsyncdir = null,
    .destroy = null,
    .access = null,
    .create = null,
    .lock = null,
    .utimens = null,
    .bmap = null,
    .ioctl = null,
    .poll = null,
    .write_buf = null,
    .read_buf = null,
    .flock = null,
    .fallocate = null,
    .copy_file_range = null,
    .lseek = null,
};

pub fn show_help(arg_progname: [*c]const u8) callconv(.C) void {
    var progname = arg_progname;
    _ = std.debug.printf("usage: %s [options] <mountpoint>\n\n", progname);
    _ = std.debug.printf("File-system specific options:\n    --name=<s>          Name of the \"hello\" file\n                        (default: \"hello\")\n    --contents=<s>      Contents \"hello\" file\n                        (default \"Hello, World!\\n\")\n\n");
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    openFiles = FileTracker.init(allocator);

    const testSourceDir = try std.fs.cwd().openDir("test-source", .{});
    const testSource = try testSourceDir.realpathAlloc(allocator, ".");
    defer allocator.free(testSource);

    const C = @import("./fsdb/fixed_buffer_content.zig").FixedBufferContent;

    var rootDb = FlatDb(C).init(arena.allocator());
    defer rootDb.deinit();

    var c1 = C.init("hello there mr foobar");
    var c2 = C.init("worldy murldy");

    try rootDb.add("hello.txt", c1);
    try rootDb.add("world.txt", c2);

    // var mdb = MetaDb.init(arena.allocator());
    // defer mdb.deinit();

    // try indexSourceByExt(allocator, testSource, &mdb);

    // if (mdb.mounted("txt")) |m| {
    //     var f = m.unwrap(@import("./fsdb/flat.zig").FlatDb);
    //     std.log.warn("txt: {any}", .{f.entries.values()});
    // }

    // init the global
    db = rootDb.idb();

    const args = try std.process.argsAlloc(arena.allocator());
    defer std.process.argsFree(arena.allocator(), args);

    log.debug("main {d}", .{args.len});
    for (args) |a| {
        log.debug("a: {s}", .{a});
    }

    _ = c.fuse_main_real(@intCast(c_int, std.os.argv.len), @ptrCast([*c][*c]u8, std.os.argv), &hello_oper, @sizeOf(c.struct_fuse_operations), null);
}

test "farts" {}
