const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

const Table = struct {
    /// Each row consists of `stride` number of columns of string indices.
    rows: std.ArrayListUnmanaged(StringIndex) = .{},
    /// Limit is 256 columns
    stride: u8,
    /// String pool, where we actually store all strings as they're variable width which is annoying
    /// to deal with in a 1D array.
    pool: std.ArrayListUnmanaged(u8) = .{},

    pub const StringIndex = enum(u32) { _ };

    pub fn addRow(self: *Table, gpa: Allocator, columns: []const []const u8) error{OutOfMemory}!void {
        assert(columns.len == self.stride); // welp, we have a bug

        // If we fail allocating anything, reset the string pool (pop the latest entries)
        // such that the table remains in a consistent state.
        const pool_reset = self.pool.items.len;
        errdefer self.pool.items.len = pool_reset;

        // Same as above, if anything fails, reset.
        const rows_reset = self.rows.items.len;
        errdefer self.rows.items.len = rows_reset;

        // Operate over all columns
        for (columns) |col| {
            // Add the start of the string to rows such that we can look it up again later.
            try self.rows.append(gpa, @enumFromInt(self.pool.items.len));

            // Add the string to the pool.
            try self.pool.appendSlice(gpa, col);

            // Null terminate the string such that we can recover it's length later on. Another
            // option would be to store the length of the string as the first few bytes but as
            // I'm not sure what you want to do with it, I'll assume your strings are on the
            // shorter side where using `mem.sliceTo` isn't costly enough to care.
            try self.pool.append(gpa, 0);
        }
    }

    pub fn render(self: *Table, writer: anytype) !void {

        // Find widest row for each column (255 is the max number of columns)
        var colWidths = [_]usize{0} ** 256;

        for (0.., self.rows.items) |n, got| {
            var col_index = @mod(n, self.stride);
            colWidths[col_index] = @max(colWidths[col_index], self.getString(got).len);
        }

        // Build table
        for (0.., self.rows.items) |n, got| {
            var col_index = @mod(n, self.stride);

            if (col_index == 0) {
                if (n > 0) {
                    try writer.writeAll("\n");
                }
                try writer.writeAll("|");
            }

            try writer.writeAll(" ");

            // Pad with max column width
            try std.fmt.format(
                writer,
                "{?s: <[1]}",
                .{ self.getString(got), colWidths[col_index] },
            );

            try writer.writeAll(" |");
        }
    }

    pub fn getString(self: *Table, string_index: StringIndex) []const u8 {
        // We stored the start of the string so we can skip to it.
        const start = self.pool.items[@intFromEnum(string_index)..];
        // Now we must find the end by searching for 0. If you have binary data you'd have to
        // use the length method here instead of searching for 0.
        return mem.sliceTo(start, 0);
    }

    pub fn deinit(self: *Table, gpa: Allocator) void {
        self.rows.deinit(gpa);
        self.pool.deinit(gpa);
        self.* = undefined;
    }
};

test Table {
    var table: Table = .{ .stride = 4 };
    defer table.deinit(testing.allocator);

    const text: []const []const u8 = &.{ "one", "two", "three", "four" };
    const number: []const []const u8 = &.{ "1", "2", "3", "4" };

    try table.addRow(testing.allocator, text);
    try table.addRow(testing.allocator, number);

    for (text, table.rows.items[0..table.stride]) |expect, got| {
        try testing.expectEqualStrings(expect, table.getString(got));
    }

    for (number, table.rows.items[table.stride .. table.stride * 2]) |expect, got| {
        try testing.expectEqualStrings(expect, table.getString(got));
    }
}
test "output full table" {
    var table: Table = .{ .stride = 3 };
    defer table.deinit(testing.allocator);

    const expected =
        \\| hello | there | alisae |
        \\| don't | walk  | there  |
    ;

    const row1: []const []const u8 = &.{ "hello", "there", "alisae" };
    const row2: []const []const u8 = &.{ "don't", "walk", "there" };

    try table.addRow(testing.allocator, row1);
    try table.addRow(testing.allocator, row2);

    var got: std.ArrayListUnmanaged(u8) = .{};

    defer got.deinit(testing.allocator);
    const w = got.writer(testing.allocator);

    try table.render(w);
    try testing.expectEqualStrings(expected, got.items);
}

test "stride of 3" {
    var table: Table = .{ .stride = 3 };
    defer table.deinit(testing.allocator);

    const beginning: []const []const u8 = &.{ "hello", "there", "alisae" };
    const end: []const []const u8 = &.{ "don't", "walk", "there" };

    try table.addRow(testing.allocator, beginning);
    try table.addRow(testing.allocator, end);

    const story = beginning ++ end;

    var it = mem.tokenize(u8, table.pool.items, "\x00");
    for (story) |word| {
        const next = it.next() orelse return error.Welp;
        try testing.expectEqualStrings(word, next);
    }

    try testing.expectEqualSlices(
        Table.StringIndex,
        &[_]Table.StringIndex{
            @enumFromInt(0),  @enumFromInt(6),  @enumFromInt(12),
            @enumFromInt(19), @enumFromInt(25), @enumFromInt(30),
        },
        table.rows.items,
    );

    for (story, table.rows.items) |expected, index| {
        try testing.expectEqualStrings(expected, table.getString(index));
    }
}
