const std = @import("std");
const yaml = @import("yaml");

const file = @embedFile("./zigmod.yml");

test {
    const doc = try yaml.parse(std.testing.allocator, file);
    defer doc.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("g982zq6e8wsvnmduerpbf8787hu85brugmngn8wf", doc.mapping.get_string("id").?);
}
