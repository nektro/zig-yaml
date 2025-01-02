const std = @import("std");
const yaml = @import("yaml");
const expect = @import("expect").expect;

const file = @embedFile("./zigmod.yml");

test {
    const doc = try yaml.parse(std.testing.allocator, file);
    defer doc.deinit(std.testing.allocator);

    try expect(doc.mapping.get_string("id").?).toEqualString("g982zq6e8wsvnmduerpbf8787hu85brugmngn8wf");
}
