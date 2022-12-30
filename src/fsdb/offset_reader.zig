const OffsetReader = @This();
ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    // size: *const fn (ptr: *anyopaque) u64,
    readAt: *const fn (ptr: *anyopaque, buf: []u8, at: u64) usize,
};

pub fn readAt(self: OffsetReader, buf: []u8, at: u64) usize {
    return self.vtable.readAt(self.ptr, buf, at);
}

pub fn size(self: OffsetReader) u64 {
    return self.vtable.size(self.ptr);
}
