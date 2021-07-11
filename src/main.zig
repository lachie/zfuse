const std = @import("std");
const mem = std.mem;
const c = @cImport({
    @cDefine("FUSE_USE_VERSION", "31");
    // @cDefine("_FILE_OFFSET_BITS","64");
    @cInclude("fuse.h");
});

const options: struct {
    filename: []const u8,
    contents: []const u8,
} = .{ .filename = "foobar", .contents = "xyz" };

const ENOENT = 2;


pub fn hello_init(conn: [*c]c.struct_fuse_conn_info, cfg: [*c]c.struct_fuse_config) callconv(.C) ?*c_void {
    
    cfg.*.kernel_cache = 1;

    return @intToPtr(?*c_void, 0);
}

pub fn hello_getattr(path: [*c]const u8, stbuf: [*c]c.struct_stat, fi: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    stbuf.* = mem.zeroes(c.struct_stat);

    const zPath: []const u8 = mem.span(path); //@ptrCast([]const u8, path);

    if (mem.eql(u8, zPath, "/")) {

        stbuf.*.st_mode = c.S_IFDIR | 0o755;
        // stbuf.*.st_mode = @bitCast(__mode_t, (@as(c_int, 16384) | @as(c_int, 493)));
        stbuf.*.st_nlink = @bitCast(c.__nlink_t, @as(c_long, @as(c_int, 2)));
        return 0;
    } else if (mem.eql(u8, zPath[1..], options.filename)) {
        stbuf.*.st_mode = @bitCast(c.__mode_t, (@as(c_int, 32768) | @as(c_int, 292)));
        stbuf.*.st_nlink = @bitCast(c.__nlink_t, @as(c_long, @as(c_int, 1)));
        stbuf.*.st_size = @bitCast(c.__off_t, options.contents.len);
        return 0;
    } else return -ENOENT;
}
pub fn hello_readdir(arg_path: [*c]const u8, buf: ?*c_void, filler: c.fuse_fill_dir_t, offset: c.off_t, fi: ?*c.struct_fuse_file_info, flags: c.enum_fuse_readdir_flags) callconv(.C) c_int {
    const path = mem.span(arg_path);
    
    if(!mem.eql(u8, path, "/")) {
        return -ENOENT;
    }
    
    _ = filler.?(buf, ".", null, @bitCast(off_t, @as(c_long, @as(c_int, 0))), @intToEnum(c.enum_fuse_fill_dir_flags, @as(c_int, 0)));
    _ = filler.?(buf, "..", null, @bitCast(off_t, @as(c_long, @as(c_int, 0))), @intToEnum(c.enum_fuse_fill_dir_flags, @as(c_int, 0)));
    _ = filler.?(buf, options.filename, null, @bitCast(off_t, @as(c_long, @as(c_int, 0))), @intToEnum(c.enum_fuse_fill_dir_flags, @as(c_int, 0)));
    return 0;
}

pub fn hello_open(arg_path: [*c]const u8, fi: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    const path = mem.span(arg_path);

    if(!mem.eql(u8, path[1..], options.filename)) {
        return -ENOENT;
    }

    
    if ((fi.?.*.flags & @as(c_int, 3)) != @as(c_int, 0)) return -@as(c_int, 13);
    return 0;
}

pub fn hello_read(arg_path: [*c]const u8, buf: [*c]u8, arg_size: usize, arg_offset: c.off_t, fi: ?*c.struct_fuse_file_info) callconv(.C) c_int {
    
    const path = mem.span(arg_path);
    var size = arg_size;

    if(!mem.eql(u8, path[1..], options.filename)) {
        return -ENOENT;
    }

    const offset = @bitCast(c_ulong, arg_offset);
    
    if(offest < path.len) {
        if((offset +% size) > path.len) {
            size = path.len -% offset;
        }
        mem.copy(u8, buf, options.contents[offset..size]) catch return 0;
    } else {
        size = 0;
    }
    return @truncate(c_uint, size);
}


pub const hello_oper: c.struct_fuse_operations = c.struct_fuse_operations{
    .getattr = hello_getattr,
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
    .open = hello_open,
    .read = hello_read,
    .write = null,
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
    _ = printf("usage: %s [options] <mountpoint>\n\n", progname);
    _ = printf("File-system specific options:\n    --name=<s>          Name of the \"hello\" file\n                        (default: \"hello\")\n    --contents=<s>      Contents \"hello\" file\n                        (default \"Hello, World!\\n\")\n\n");
}


pub export fn mainC(argc: c_int, argv: [*c][*c]u8) c_int {
    var args: c.struct_fuse_args = c.struct_fuse_args{
        .argc = argc,
        .argv = argv,
        .allocated = @as(c_int, 0),
    };

    // if (c.fuse_opt_parse(&args, @ptrCast(?*c_void, &options), &option_spec, null) == -@as(c_int, 1)) return 1;
    // if (options.show_help != 0) {
    //     c.show_help(argv[@intCast(c_uint, @as(c_int, 0))]);
    //     _ = @sizeOf(c_int);
    //     _ = (blk: {
    //         break :blk if (c.fuse_opt_add_arg(&args, "--help") == @as(c_int, 0)) {} else c.__assert_fail("fuse_opt_add_arg(&args, \"--help\") == 0", "./libfuse/example/hello.c", @bitCast(c_uint, @as(c_int, 172)), "int main(int, char **)");
    //     });
    //     args.argv[@intCast(c_uint, @as(c_int, 0))][@intCast(c_uint, @as(c_int, 0))] = @bitCast(u8, @truncate(i8, @as(c_int, '\x00')));
    // }

   const ret = c.fuse_main_real(args.argc, args.argv, &hello_oper, @sizeOf(c.struct_fuse_operations), (@intToPtr(?*c_void, @as(c_int, 0))));
    c.fuse_opt_free_args(&args);
    return ret;
}


fn fuseMain(allocator: *std.mem.Allocator) !void {
    
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const args = try std.process.argsAlloc(&arena.allocator);
    defer std.process.argsFree(&arena.allocator, args);

    const rv = mainC(@intCast(c_int, args.len), @ptrCast([*c][*c]u8, args));
}