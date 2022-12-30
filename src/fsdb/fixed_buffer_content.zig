const std = @import("std");
const OffsetReader = @import("./offset_reader.zig");

pub const FixedBufferContent = struct {
    const Self = @This();

    const Stream = std.io.FixedBufferStream([]const u8);

    // buffer: []u8,
    stream: Stream,

    pub fn offsetReader(self: *Self) OffsetReader {
        return .{
            .ptr = self,
            .vtable = &.{
                // .size = size,
                .readAt = readAt,
            },
        };
    }

    pub fn init(buf: []const u8) FixedBufferContent {
        return .{
            // .buffer = buf,
            .stream = Stream{ .buffer = buf, .pos = 0 },
        };
    }

    pub fn size(self: Self) u64 {
        return self.stream.buffer.len;
    }
    fn readAt(ptr: *anyopaque, buf: []u8, at: u64) usize {
        const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), ptr));

        self.stream.seekTo(at) catch return 0;
        return self.stream.read(buf) catch 0;
    }
};
