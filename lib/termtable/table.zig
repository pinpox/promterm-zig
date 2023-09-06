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

        // TODO make this a dynamic length
        var colWidths = [_]usize{ 0, 0, 0, 0, 0, 0, 0, 0 };
        // defer allocator.free(colWidths);

        // Find widest row for each column
        for (0.., self.rows.items) |n, got| {
            var col_index = @mod(n, self.stride);
            colWidths[col_index] = @max(colWidths[col_index], self.getString(got).len);
        }

        std.debug.print("WIDTHS: {any}\n", .{colWidths});

        for (0.., self.rows.items) |n, got| {
            var col_index = @mod(n, self.stride);

            // std.debug.print("{}", .{col_index});

            if (col_index == 0) {
                if (n > 0) {
                    try writer.writeAll("\n");
                }
                try writer.writeAll("|");
            }

            try writer.writeAll(" ");
            // std.debug.print("Formatting {s} with width {}\n", .{ self.getString(got), colWidths[col_index] });

            // const string = try std.fmt.allocPrint(
            //     allocator,
            //     "{?s: <[1]}",
            //     .{ self.getString(got), colWidths[col_index] },
            // );
            // defer allocator.free(string);

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

//const std = @import("std");
//const print = std.debug.print;

//const Field = struct {
//    text: []u8 = "",
//    bold: bool = false,
//    italic: bool = false,
//    underline: bool = false,
//    alignment: Alignment = Alignment.left,
//    color: Color = Color.default,
//};

////     Red: \u001b[31m
////     Reset: \u001b[0m
////print u"\u001b[31mHelloWorld"

//const Color = enum {
//    default,
//    red,
//};

//const Alignment = enum {
//    left,
//    right,
//    center,
//};

//// const Row = []Field;

//// fn red(in: []u8) []u8 {
////     return in;
//// }
//const mem = std.mem;
//const assert = std.debug.assert;

//// const Allocator = std.mem.Allocator;

//// const Table = struct {
////     /// Each row consists of `stride` number of columns of string indices.
////     rows: std.ArrayListUnmanaged(String) = .{},
////     /// Limit is 256 columns
////     stride: u8,
////     /// String pool, where we actually store all strings as they're variable width which is annoying
////     /// to deal with in a 1D array.
////     pool: std.ArrayListUnmanaged(u8) = .{},

////     allocator: std.mem.Allocator,

////     pub const String = enum(u32) { _ };

////     pub fn init(nCols: usize, allocator: std.mem.Allocator) Table {
////         var rows = std.ArrayList(Row).init(std.heap.page_allocator);
////         defer rows.deinit();
////         return Table{ .stride = nCols, .allocator = allocator };
////     }

////     pub fn empty(self: Table) bool {
////         return self.rows.items.len == 0;
////     }

////     pub fn addRow(self: *Table, columns: []const u8) error{OutOfMemory}!void {
////         assert(columns.len == self.stride); // welp, we have a bug

////         // If we fail allocating anything, reset the string pool (pop the latest entries)
////         // such that the table remains in a consistent state.
////         const pool_reset = self.pool.items.len;
////         errdefer self.pool.items.len = pool_reset;

////         // Same as above, if anything fails, reset.
////         const rows_reset = self.rows.items.len;
////         errdefer self.rows.items.len = rows_reset;

////         // Operate over all columns
////         for (columns) |col| {
////             // Add the start of the string to rows such that we can look it up again later.
////             try self.rows.append(@enumFromInt(self.pool.items.len));

////             // Add the string to the pool.
////             try self.pool.appendSlice(self.allocator, col);

////             // Null terminate the string such that we can recover it's length later on. Another
////             // option would be to store the length of the string as the first few bytes but as
////             // I'm not sure what you want to do with it, I'll assume your strings are on the
////             // shorter side where using `mem.sliceTo` isn't costly enough to care.
////             try self.pool.append(0);
////         }
////     }

////     pub fn getString(self: *Table, string: String) []const u8 {
////         // We stored the start of the string so we can skip to it.
////         const start = self.pool.items[@intFromEnum(string)..];
////         // Now we must find the end by searching for 0. If you have binary data you'd have to
////         // use the length method here instead of searching for 0.
////         return mem.sliceTo(start, 0);
////     }
//// };

//const Table = struct {
//    rows: std.ArrayList([]Field),
//    nCols: usize,
//    allocator: std.mem.Allocator,

//    pub fn init(nCols: usize, allocator: std.mem.Allocator) Table {
//        var rows = std.ArrayList([]Field).init(std.heap.page_allocator);
//        defer rows.deinit();
//        return Table{ .rows = rows, .nCols = nCols, .allocator = allocator };
//    }

//    pub fn empty(self: Table) bool {
//        print("LENGTH: {}\n", .{self.rows.items.len});
//        return self.rows.items.len == 0;
//    }

//    pub fn addRow(self: *Table, row: []Field) !void {

//        // Check the row has the correct number of colums
//        if ((row.len != self.nCols) and !self.empty()) {
//            print("Tried to add row with {} columns, while table is {} wide", .{ row.len, self.nCols });
//            return error.WrongNumberOfColumns;
//        } else {
//            // print("ADDING {}\n", .{row});

//            // TODO fix this. Currently broken
//            try self.rows.append(row);

//            // const memory = try self.allocator.create(Row);
//            // try self.rows.append(memory);

//            // const memory = try self.allocator.alloc(Row, 1);
//            // defer self.allocator.free(memory);
//            // try self.rows.append(memory);
//        }
//        // print("ROWS is now {s}\n", .{self.rows.items});

//        return;
//    }

//    pub fn string(self: Table) ![]u8 {
//        var out = std.ArrayList(u8).init(self.allocator);
//        defer out.deinit();

//        var colWidths = try self.allocator.alloc(usize, self.nCols);
//        defer self.allocator.free(colWidths);

//        if (self.empty()) {
//            return "";
//        }
//        print("not empty", .{});

//        // Find widest row for each column
//        for (0..self.nCols) |i| {
//            for (self.rows.items) |row| {
//                if (row.len > 0) {
//                    colWidths[i] = @max(colWidths[i], row[i].text.len);
//                }
//            }
//        }

//        // Build output
//        try out.appendSlice("| ");

//        for (self.rows.items) |row| {
//            for (0..self.nCols) |i| {
//                if (row.len > 0) {
//                    try out.appendSlice(row[i].text);
//                }
//            }

//            try out.append('\n');
//        }

//        // print("| {?s: <[4]} | {?s: <[5]} | {?s: <[6]} | {?s: <[7]} |\n", .{
//        //     "Instance",
//        //     "State",
//        //     "Alert",
//        //     "Description",
//        //     max_lengths[0],
//        //     max_lengths[1],
//        //     max_lengths[2],
//        //     max_lengths[3],
//        // });

//        // for (self.rows.items) |row| {
//        //     try colWidth.append(0);
//        //     print("Row len: {}\n", .{row.items.len});
//        //     for (0.., row.items) |i, c| {
//        //         print("cols {} len: {} {s}\n", .{ i, c.len, c });

//        //         //     colWidth.items[i] = @max(colWidth.items[i], c.len);
//        //     }
//        // }

//        return out.items;
//        // return "test";
//    }
//};

//test "creating a 4x3 table" {

//    // Table:
//    const expected =
//        \\| h1           | h2 | h3                       | h4 |
//        \\| a long field | b  | c                        | d  |
//        \\| e            | f  | g                        | h  |
//        \\| i            | j  | this one is alsow longer | l  |
//    ;

//    // Create table with 4 columns
//    var table = Table.init(4, std.testing.allocator);

//    var field2 = Field{};
//    _ = field2;
//    var field3 = Field{};
//    _ = field3;
//    var field4 = Field{};
//    _ = field4;
//    var field5 = Field{};
//    _ = field5;
//    var field6 = Field{};
//    _ = field6;
//    var field7 = Field{};
//    _ = field7;
//    var field8 = Field{};
//    _ = field8;
//    var field9 = Field{};
//    _ = field9;
//    var field10 = Field{};
//    _ = field10;
//    var field11 = Field{};
//    _ = field11;
//    var field12 = Field{};
//    _ = field12;
//    var field13 = Field{};
//    _ = field13;
//    var field14 = Field{};
//    _ = field14;
//    var field15 = Field{};
//    _ = field15;
//    var field16 = Field{};
//    _ = field16;

//    var row1 = [_]Field{};
//    _ = row1;
//    // var row2 = [_]Row{ field5, field6, field7, field8 };
//    // var row3 = [_]Row{ field9, field10, field11, field12 };
//    // var row4 = [_]Row{ field13, field14, field15, field16 };

//    // var row1 = [_][]u8{ "h1", "h2", "h3", "h4" };
//    // var row2 = [_][]u8{ "a long field", "b", "c", "d" };
//    // var row3 = [_][]u8{ "e", "f", "g", "h" };
//    // var row4 = [_][]u8{ "i", "j", "this one is also longer", "l" };

//    // Add rows to table
//    try table.addRow(&[_]Field{});
//    // table.addRow(row2);
//    // table.addRow(row3);
//    // table.addRow(row4);
//    //
//    var result = try table.string();

//    // Get formatted table
//    try std.testing.expect(mem.eql(u8, result, expected));
//}

//const testing = std.testing;
//const Allocator = std.mem.Allocator;

//const Table = struct {
//    /// Each row consists of `stride` number of columns of string indices.
//    rows: std.ArrayListUnmanaged(String) = .{},
//    /// Limit is 256 columns
//    stride: u8,
//    /// String pool, where we actually store all strings as they're variable width which is annoying
//    /// to deal with in a 1D array.
//    pool: std.ArrayListUnmanaged(u8) = .{},

//    pub const String = enum(u32) { _ };

//    pub fn addRow(self: *Table, gpa: Allocator, columns: []const []const u8) error{OutOfMemory}!void {
//        assert(columns.len == self.stride); // welp, we have a bug

//        // If we fail allocating anything, reset the string pool (pop the latest entries)
//        // such that the table remains in a consistent state.
//        const pool_reset = self.pool.items.len;
//        errdefer self.pool.items.len = pool_reset;

//        // Same as above, if anything fails, reset.
//        const rows_reset = self.rows.items.len;
//        errdefer self.rows.items.len = rows_reset;

//        // Operate over all columns
//        for (columns) |col| {
//            // Add the start of the string to rows such that we can look it up again later.
//            try self.rows.append(gpa, @enumFromInt(self.pool.items.len));

//            // Add the string to the pool.
//            try self.pool.appendSlice(gpa, col);

//            // Null terminate the string such that we can recover it's length later on. Another
//            // option would be to store the length of the string as the first few bytes but as
//            // I'm not sure what you want to do with it, I'll assume your strings are on the
//            // shorter side where using `mem.sliceTo` isn't costly enough to care.
//            try self.pool.append(gpa, 0);
//        }
//    }

//    pub fn getString(self: *Table, string: String) []const u8 {
//        // We stored the start of the string so we can skip to it.
//        const start = self.pool.items[@intFromEnum(string)..];
//        // Now we must find the end by searching for 0. If you have binary data you'd have to
//        // use the length method here instead of searching for 0.
//        return mem.sliceTo(start, 0);
//    }

//    pub fn deinit(self: *Table, gpa: Allocator) void {
//        self.rows.deinit(gpa);
//        self.pool.deinit(gpa);
//        self.* = undefined;
//    }
//};

//test Table {
//    var table: Table = .{ .stride = 4 };
//    defer table.deinit(testing.allocator);

//    const text: []const []const u8 = &.{ "one", "two", "three", "four" };
//    const number: []const []const u8 = &.{ "1", "2", "3", "4" };

//    try table.addRow(testing.allocator, text);
//    try table.addRow(testing.allocator, number);

//    for (text, table.rows.items[0..table.stride]) |expect, got| {
//        try testing.expectEqualStrings(expect, table.getString(got));
//    }

//    for (number, table.rows.items[table.stride .. table.stride * 2]) |expect, got| {
//        try testing.expectEqualStrings(expect, table.getString(got));
//    }
//}
