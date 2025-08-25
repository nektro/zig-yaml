const std = @import("std");
const string = []const u8;
const extras = @import("extras");

const c = @cImport({
    @cInclude("yaml.h");
});

//
//

pub const Stream = struct {
    docs: []const Document,

    pub fn deinit(self: *const Stream, alloc: std.mem.Allocator) void {
        for (self.docs) |*item| item.deinit(alloc);
        alloc.free(self.docs);
    }
};

pub const Document = union(enum) {
    mapping: Mapping,
    sequence: Sequence,

    pub fn deinit(self: *const Document, alloc: std.mem.Allocator) void {
        switch (self.*) {
            .mapping => |m| m.deinit(alloc),
            .sequence => |s| {
                for (s) |*item| item.deinit(alloc);
                alloc.free(s);
            },
        }
    }
};

pub const Item = union(enum) {
    event: Token,
    kv: Key,
    mapping: Mapping,
    sequence: Sequence,
    string: string,
    stream: Stream,

    pub fn deinit(self: *const Item, alloc: std.mem.Allocator) void {
        switch (self.*) {
            .event => {},
            .kv => |kv| kv.deinit(alloc),
            .mapping => |m| m.deinit(alloc),
            .sequence => |s| {
                for (s) |*item| item.deinit(alloc);
                alloc.free(s);
            },
            .string => |s| alloc.free(s),
            .stream => |s| s.deinit(alloc),
        }
    }

    pub fn format(self: Item, comptime fmt: string, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        _ = fmt;
        _ = options;

        try writer.writeAll("Item{");
        switch (self) {
            .event => {
                try std.fmt.format(writer, "event {}", .{self.event});
            },
            .kv, .stream => {
                unreachable;
            },
            .mapping => {
                try std.fmt.format(writer, "{}", .{self.mapping});
            },
            .sequence => {
                try writer.writeAll("[ ");
                for (self.sequence) |it| {
                    try std.fmt.format(writer, "{}, ", .{it});
                }
                try writer.writeAll("]");
            },
            .string => {
                try std.fmt.format(writer, "{s}", .{self.string});
            },
        }
        try writer.writeAll("}");
    }
};

pub const Sequence = []const Item;

pub const Key = struct {
    key: string,
    value: Value,

    pub fn deinit(self: *const Key, alloc: std.mem.Allocator) void {
        alloc.free(self.key);
        self.value.deinit(alloc);
    }
};

pub const Value = union(enum) {
    string: string,
    mapping: Mapping,
    sequence: Sequence,

    pub fn deinit(self: *const Value, alloc: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| alloc.free(s),
            .mapping => |*m| {
                m.deinit(alloc);
            },
            .sequence => |s| {
                for (s) |*item| item.deinit(alloc);
                alloc.free(s);
            },
        }
    }

    pub fn format(self: Value, comptime fmt: string, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        _ = fmt;
        _ = options;

        try writer.writeAll("Value{");
        switch (self) {
            .string => {
                try std.fmt.format(writer, "{s}", .{self.string});
            },
            .mapping => {
                try std.fmt.format(writer, "{}", .{self.mapping});
            },
            .sequence => {
                try writer.writeAll("[ ");
                for (self.sequence) |it| {
                    try std.fmt.format(writer, "{}, ", .{it});
                }
                try writer.writeAll("]");
            },
        }
        try writer.writeAll("}");
    }
};

pub const Mapping = struct {
    items: []const Key,

    pub fn deinit(self: *const Mapping, alloc: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(alloc);
        alloc.free(self.items);
    }

    pub fn get(self: Mapping, k: string) ?Value {
        for (self.items) |item| {
            if (std.mem.eql(u8, item.key, k)) {
                return item.value;
            }
        }
        return null;
    }

    pub fn getT(self: Mapping, k: string, comptime f: std.meta.FieldEnum(Value)) ?std.meta.FieldType(Value, f) {
        for (self.items) |item| {
            if (std.mem.eql(u8, item.key, k)) {
                return @field(item.value, @tagName(f));
            }
        }
        return null;
    }

    pub fn get_string(self: Mapping, k: string) ?string {
        return self.getT(k, .string);
    }

    pub fn get_string_array(self: Mapping, alloc: std.mem.Allocator, k: string) ![]string {
        var list = std.ArrayList(string).init(alloc);
        errdefer list.deinit();
        if (self.get(k)) |val| {
            if (val == .sequence) {
                for (val.sequence) |item| {
                    if (item != .string) {
                        continue;
                    }
                    try list.append(item.string);
                }
            }
        }
        return list.toOwnedSlice();
    }

    pub fn getMap(self: Mapping, k: string) ?Mapping {
        return self.getT(k, .mapping);
    }

    pub fn format(self: Mapping, comptime fmt: string, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        _ = fmt;
        _ = options;

        try writer.writeAll("{ ");
        for (self.items) |it| {
            try std.fmt.format(writer, "{s}: ", .{it.key});
            try std.fmt.format(writer, "{}, ", .{it.value});
        }
        try writer.writeAll("}");
    }
};

pub const Token = c.yaml_event_t;
pub const TokenList = []const Token;

//
//

pub fn parse(alloc: std.mem.Allocator, input: string) !Document {
    var parser: c.yaml_parser_t = undefined;
    _ = c.yaml_parser_initialize(&parser);
    defer c.yaml_parser_delete(&parser);

    const lines = try split(alloc, input, '\n');
    defer alloc.free(lines);

    _ = c.yaml_parser_set_input_string(&parser, input.ptr, input.len);

    var all_events = std.ArrayList(Token).init(alloc);
    defer all_events.deinit();
    var event: Token = undefined;
    while (true) {
        const p = c.yaml_parser_parse(&parser, &event);
        if (p == 0) {
            break;
        }

        const et = event.type;
        try all_events.append(event);
        c.yaml_event_delete(&event);

        if (et == c.YAML_STREAM_END_EVENT) {
            break;
        }
    }

    var p = Parser{
        .alloc = alloc,
        .tokens = all_events.items,
        .lines = lines,
        .index = 0,
    };
    const stream = try p.parse();
    defer alloc.free(stream.docs);
    return stream.docs[0];
}

pub const Parser = struct {
    alloc: std.mem.Allocator,
    tokens: TokenList,
    lines: []const string,
    index: usize,

    pub fn parse(self: *Parser) !Stream {
        const item = try parse_item(self, null);
        return item.stream;
    }

    fn next(self: *Parser) !Token {
        if (self.index >= self.tokens.len) {
            return error.YamlEndOfStream;
        }
        defer self.index += 1;
        return self.tokens[self.index];
    }
};

pub const Error =
    std.mem.Allocator.Error ||
    error{ YamlUnexpectedToken, YamlEndOfStream };

fn parse_item(p: *Parser, start: ?Token) Error!Item {
    const tok = start orelse try p.next();
    return switch (tok.type) {
        c.YAML_STREAM_START_EVENT => Item{ .stream = try parse_stream(p) },
        c.YAML_MAPPING_START_EVENT => Item{ .mapping = try parse_mapping(p) },
        c.YAML_SEQUENCE_START_EVENT => Item{ .sequence = try parse_sequence(p) },
        c.YAML_SCALAR_EVENT => Item{ .string = try get_event_string(tok, p) },
        else => unreachable,
    };
}

fn parse_stream(p: *Parser) Error!Stream {
    var res = std.ArrayList(Document).init(p.alloc);
    errdefer res.deinit();

    while (true) {
        const tok = try p.next();
        if (tok.type == c.YAML_STREAM_END_EVENT) {
            return Stream{ .docs = try res.toOwnedSlice() };
        }
        if (tok.type != c.YAML_DOCUMENT_START_EVENT) {
            return error.YamlUnexpectedToken;
        }
        try res.append(try parse_document(p));
    }
}

fn parse_document(p: *Parser) Error!Document {
    const tok = try p.next();
    switch (tok.type) {
        c.YAML_MAPPING_START_EVENT => {
            const item = try parse_item(p, tok);
            const tok2 = try p.next();
            if (tok2.type != c.YAML_DOCUMENT_END_EVENT) {
                return error.YamlUnexpectedToken;
            }
            return Document{ .mapping = item.mapping };
        },
        c.YAML_SEQUENCE_START_EVENT => {
            const item = try parse_item(p, tok);
            const tok2 = try p.next();
            if (tok2.type != c.YAML_DOCUMENT_END_EVENT) {
                return error.YamlUnexpectedToken;
            }
            return Document{ .sequence = item.sequence };
        },
        else => {
            return error.YamlUnexpectedToken;
        },
    }
}

fn parse_mapping(p: *Parser) Error!Mapping {
    var res = std.ArrayList(Key).init(p.alloc);
    errdefer res.deinit();

    while (true) {
        const tok = try p.next();
        if (tok.type == c.YAML_MAPPING_END_EVENT) {
            return Mapping{ .items = try res.toOwnedSlice() };
        }
        if (tok.type != c.YAML_SCALAR_EVENT) {
            return error.YamlUnexpectedToken;
        }
        try res.append(Key{
            .key = try get_event_string(tok, p),
            .value = try parse_value(p),
        });
    }
}

fn parse_value(p: *Parser) Error!Value {
    const item = try parse_item(p, null);
    return switch (item) {
        .mapping => |x| Value{ .mapping = x },
        .sequence => |x| Value{ .sequence = x },
        .string => |x| Value{ .string = x },
        else => unreachable,
    };
}

fn parse_sequence(p: *Parser) Error!Sequence {
    var res = std.ArrayList(Item).init(p.alloc);
    errdefer res.deinit();

    while (true) {
        const tok = try p.next();
        if (tok.type == c.YAML_SEQUENCE_END_EVENT) {
            return try res.toOwnedSlice();
        }
        try res.append(try parse_item(p, tok));
    }
}

fn get_event_string(event: Token, p: *const Parser) !string {
    const sm = event.start_mark;
    const em = event.end_mark;
    const lines = p.lines;
    if (sm.line != em.line) {
        const starter = lines[sm.line][sm.column..];
        std.debug.assert(starter.len == 1);
        switch (starter[0]) {
            '|' => {
                var list = std.ArrayList(u8).init(p.alloc);
                errdefer list.deinit();
                var i = sm.line + 1;
                while (i < em.line) : (i += 1) {
                    try list.appendSlice(std.mem.trimLeft(u8, lines[i], " "));
                    try list.append('\n');
                }
                return try list.toOwnedSlice();
            },
            else => @panic("TODO"),
        }
    }
    const s = lines[sm.line][sm.column..em.column];
    if (s.len < 2) return try p.alloc.dupe(u8, s);
    if (s[0] == '"' and s[s.len - 1] == '"') return try p.alloc.dupe(u8, std.mem.trim(u8, s, "\""));
    if (s[0] == '\'' and s[s.len - 1] == '\'') return try p.alloc.dupe(u8, std.mem.trim(u8, s, "'"));
    return try p.alloc.dupe(u8, s);
}

//
//

fn split(alloc: std.mem.Allocator, in: string, delim: u8) ![]string {
    var list = std.ArrayList(string).init(alloc);
    errdefer list.deinit();

    var iter = std.mem.splitScalar(u8, in, delim);
    while (iter.next()) |str| {
        try list.append(str);
    }
    return try list.toOwnedSlice();
}
