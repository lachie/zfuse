const std = @import("std");

pub const HeadRest = struct {
    head: []const u8,
    rest: []const u8,
    root: bool = false,

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        if (fmt.len != 0) std.fmt.invalidFmtError(fmt, self);
        _ = options;
        try std.fmt.format(writer, "{{h:\"{s}\" r:\"{s}\"}}", .{ self.head, self.rest });
    }
};
pub fn splitPath(path: []const u8) HeadRest {
    if (path.len == 0 or (path.len == 1 and path[0] == '/')) {
        return .{
            .root = true,
            .head = "",
            .rest = "",
        };
    }
    if (std.mem.indexOfScalarPos(u8, path[0..], 1, '/')) |slash| {
        return .{
            .head = path[1..slash],
            .rest = path[slash..],
        };
    } else {
        return .{
            .head = path[1..],
            .rest = "",
        };
    }
}

fn testSplitPath(path: []const u8, head: []const u8, rest: []const u8) !void {
    const sp = splitPath(path);
    std.log.warn("path {s} -> sp head:|{s}| rest:|{s}|", .{ path, sp.head, sp.rest });
    try std.testing.expectEqualSlices(u8, head, sp.head);
    try std.testing.expectEqualSlices(u8, rest, sp.rest);
}
test "splitPath" {
    try testSplitPath("/", "", "");
    try testSplitPath("/hi", "hi", "");
    try testSplitPath("/hi/", "hi", "/");
    try testSplitPath("/hi/there", "hi", "/there");
    try testSplitPath("/hi/there/mr/friendo/", "hi", "/there/mr/friendo/");
}
