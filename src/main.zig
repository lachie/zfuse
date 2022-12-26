const std = @import("std");
const mem = std.mem;
const c = @cImport({
    @cDefine("FUSE_USE_VERSION", "31");
    // @cDefine("_FILE_OFFSET_BITS","64");
    @cInclude("fuse.h");
    @cInclude("errno.h");
});
const dbL = @import("./db.zig");

const log = std.log.scoped(.main);

var db: dbL.Db = undefined;

// var options: struct {
//     filename: []const u8,
//     contents: []const u8,
// } = .{ .filename = "foobar", .contents = "xyz" };

const ENOENT = 2;
const EACCES = 13;

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

    // /** Padding.  Reserved for future use*/
    padding: u25,
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

    return @intToPtr(?*anyopaque, 0);
}

// fn tryInt() {}

pub fn hello_getattr(arg_path: [*c]const u8, stbuf: [*c]c.struct_stat, _: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    stbuf.* = mem.zeroes(c.struct_stat);

    const path: []const u8 = mem.span(arg_path); //@ptrCast([]const u8, path);

    log.debug("hello_getattr {s}", .{path});

    if (db.get(path)) |entry| {
        log.debug("entry {any}", .{entry});
        switch (entry.type) {
            .dir => {
                stbuf.*.st_mode = c.S_IFDIR | 0o755;
                stbuf.*.st_nlink = 2;
            },
            .file => {
                stbuf.*.st_mode = c.S_IFREG | 0o444;
                stbuf.*.st_nlink = 1;
                stbuf.*.st_size = @intCast(c.off_t, entry.len());
            },
        }
        return 0;
    } else {
        return -c.ENOENT;
    }
}

pub fn hello_readdir(arg_path: [*c]const u8, buf: ?*anyopaque, maybe_filler: c.fuse_fill_dir_t, _: c.off_t, _: ?*c.struct_fuse_file_info, _: c.enum_fuse_readdir_flags) callconv(.C) c_int {
    if (maybe_filler) |filler| {
        const path = mem.span(arg_path);

        log.debug("hello_readdir {s}", .{path});

        if (db.get(path)) |entry| {
            switch (entry.type) {
                .dir => {
                    var out_flags: c.fuse_fill_dir_flags = 0;
                    _ = filler(buf, ".", null, 0, out_flags);
                    _ = filler(buf, "..", null, 0, out_flags);

                    var children = db.getChildren(entry);
                    while (children.next()) |child| {
                        // var basename_scratch = std.BoundedArray(u8, 256).init(child.basename.len + 1) catch return -c.EIO;

                        out_flags = 0;
                        log.debug("    readdir {s}", .{child.basename});

                        // std.mem.copy(u8, basename_scratch.slice(), child.basename);
                        // basename_scratch.set(child.basename.len, 0);

                        // const cstr = @ptrCast([*c]const u8, child.basename);
                        // const cstr: [*c]const u8 = basename_scratch.constSlice();

                        _ = filler(buf, child.basename.ptr, null, 0, out_flags);
                    }
                    return 0;
                },
                else => {},
            }
        }
    }
    return -c.ENOENT;
}

pub fn hello_open(arg_path: [*c]const u8, arg_fi: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    const path = mem.span(arg_path);

    log.debug("hello_open |{s}|", .{path});

    if (db.get(path)) |entry| {
        log.debug("   entry {s}", .{entry.path});
        const fi = @ptrCast(*fuse_file_info, @alignCast(@alignOf(fuse_file_info), arg_fi));

        if (fi.flags & std.os.O.RDONLY == 0) {
            return 0;
        } else if (fi.flags & std.os.O.WRONLY == 0) {
            return 0;
        } else if (fi.flags & std.os.O.RDWR == 0) {
            return 0;
        }

        // if ((fi.*.flags & @as(c_int, c.O_ACCMODE)) != 0)
        return -EACCES;
    }

    return -ENOENT;
}

pub fn hello_read(arg_path: [*c]const u8, arg_buf: [*c]u8, arg_size: usize, arg_offset: c.off_t, _: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    const path = mem.span(arg_path);
    log.debug("hello_read {s} buf size: {d} at offset {d}", .{ path, arg_size, arg_offset });

    var size = arg_size;

    if (db.get(path)) |entry| {
        const offset = @bitCast(c_ulong, arg_offset);

        size = entry.read(arg_buf[0..arg_size], offset);

        return @intCast(c_int, size);
    }
    return -ENOENT;
}

pub fn hello_write(arg_path: [*c]const u8, arg_buf: [*c]const u8, arg_size: usize, arg_offset: c.off_t, _: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    const path = mem.span(arg_path);

    log.debug("hello_write {s} buf size: {d} at offset {d}", .{ path, arg_size, arg_offset });
    if (db.getMut(path)) |entry| {
        const offset = @bitCast(c_ulong, arg_offset);

        const size = entry.write(arg_buf[0..arg_size], offset) catch return -c.EIO;

        return @intCast(c_int, size);
    }

    return -c.ENOENT;
}

pub fn hello_mknod(arg_path: [*c]const u8, mode: c.mode_t, _: c.dev_t) callconv(.C) c_int {
    const path = mem.span(arg_path);

    log.debug("hello_mknod |{s}|", .{path});

    if ((mode & @bitCast(c.mode_t, c.S_IFMT)) != @bitCast(c.mode_t, c.S_IFREG)) return -c.EPERM;

    db.mknod(path) catch return -c.EPERM;

    db.debug();

    return 0;
}

pub fn hello_unlink(path: [*c]const u8) callconv(.C) c_int {
    if (db.del(mem.span(path))) {
        return 0;
    }
    return -c.ENOENT;
}

pub fn hello_utimens(arg_path: [*c]const u8, arg_times: [*c]const c.struct_timespec, _: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    const path = mem.span(arg_path);
    log.debug("hello_utimens |{s}| {any}", .{ path, arg_times });
    if (db.getMut(path)) |_| {
        // TODO update times
        return 0;
    }
    return -c.ENOENT;
}

pub const hello_oper: c.struct_fuse_operations = c.struct_fuse_operations{
    .getattr = hello_getattr,
    .readlink = null,
    .mknod = hello_mknod,
    .mkdir = null,
    .unlink = hello_unlink,
    .rmdir = null,
    .symlink = null,
    .rename = null,
    .link = null,
    .chmod = null,
    .chown = null,
    .truncate = null,
    .open = hello_open,
    .read = hello_read,
    .write = hello_write,
    .statfs = null,
    .flush = null,
    .release = null,
    .fsync = null,
    .setxattr = null,
    .getxattr = null,
    .listxattr = null,
    .removexattr = null,
    .opendir = null,
    .readdir = hello_readdir,
    .releasedir = null,
    .fsyncdir = null,
    .init = hello_init,
    .destroy = null,
    .access = null,
    .create = null,
    .lock = null,
    .utimens = hello_utimens,
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

pub const option_spec2 = [1]c.struct_fuse_opt{
    // c.struct_fuse_opt{
    //     .templ = "-h",
    //     .offset = @intCast(c_ulong, @ptrToInt(show_help)),
    //     .value = @as(c_int, 1),
    // },
    c.struct_fuse_opt{
        .templ = null,
        .offset = @bitCast(c_ulong, @as(c_long, @as(c_int, 0))),
        .value = @as(c_int, 0),
    },
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const test_source = "test-source";

    // note: global
    db = try dbL.dbSource(arena.allocator(), test_source);
    defer db.deinit();

    try db.putString("/foobar", "hello, world!\n");

    //std.os.argv;

    const args = try std.process.argsAlloc(arena.allocator());
    defer std.process.argsFree(arena.allocator(), args);

    log.debug("main {d}", .{args.len});
    for (args) |a| {
        log.debug("a: {s}", .{a});
    }

    // var fuse_args: c.struct_fuse_args = c.struct_fuse_args{
    //     .argc = @intCast(c_int, args.len),
    //     .argv = @ptrCast([*c][*c]u8, args),
    //     .allocated = @as(c_int, 0),
    // };

    // if(c.fuse_opt_parse(&fuse_args, @ptrCast(?*c_void, &options), @ptrCast([*c]const c.struct_fuse_opt, &option_spec2), null) == -1) {
    //     return error.FuseArgsParseFailed;
    // }

    // const ret = c.fuse_main_real(fuse_args.argc, fuse_args.argv, &hello_oper, @sizeOf(c.struct_fuse_operations), null);

    _ = c.fuse_main_real(@intCast(c_int, std.os.argv.len), @ptrCast([*c][*c]u8, std.os.argv), &hello_oper, @sizeOf(c.struct_fuse_operations), null);

    // const ret = c.fuse_main(args.argc, args.argv, &hello_oper, null);
    // c.fuse_opt_free_args(&fuse_args);

    // parse ret
}
