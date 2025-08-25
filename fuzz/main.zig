const std = @import("std");
const yaml = @import("yaml");
const nfs = @import("nfs");

pub export fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const stdin = nfs.stdin();
    const input = stdin.readToEndAlloc(allocator, 1024 * 1024, null) catch @panic("too big");
    defer allocator.free(input);

    const doc = yaml.parse(allocator, input) catch return;
    defer doc.deinit(allocator);
}
