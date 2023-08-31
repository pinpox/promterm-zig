const std = @import("std");
const allocator = std.heap.page_allocator;

const print = std.debug.print;

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    print("All your {s} are belong to us.\n", .{"codebase"});

    const url = "https://vpn.prometheus.pablo.tools/api/v1/alerts";

    var json = getJSON(url) catch |err| blk: {
        // do things
        // print("{e}", err);
        // print("unable to add one: {s}\n", .{@errorName(err)});
        print("Failed to fetch {s}: {s}\n", .{ url, @errorName(err) });
        break :blk "";
    };
    _ = json;

    const alerts = try std.json.parseFromSlice(Alerts, allocator, test_json, .{ .ignore_unknown_fields = true });
    defer alerts.deinit();

    print("{s}\n", .{alerts.value.status});
    print("{?s}\n", .{alerts.value.data.alerts[0].state});

    var max_lengths = [_]usize{ 0, 0, 0, 0 };

    for (alerts.value.data.alerts) |a| {
        max_lengths[0] = @max(max_lengths[0], a.labels.instance.len);
        max_lengths[1] = @max(max_lengths[1], a.state.len);
        max_lengths[2] = @max(max_lengths[2], a.labels.alertname.len);
        max_lengths[3] = @max(max_lengths[3], a.annotations.description.len);
    }

    print("| {?s: <[4]} | {?s: <[5]} | {?s: <[6]} | {?s: <[7]} |\n", .{
        "Instance",
        "State",
        "Alert",
        "Description",
        max_lengths[0],
        max_lengths[1],
        max_lengths[2],
        max_lengths[3],
    });

    print("├─{?s:-<[4]}─┼─{?s:-<[5]}─┼─{?s:-<[6]}─┼─{?s:-<[7]}─┤\n", .{
        "",
        "",
        "",
        "",
        max_lengths[0],
        max_lengths[1],
        max_lengths[2],
        max_lengths[3],
    });

    for (alerts.value.data.alerts) |a| {
        print("| {?s: <[4]} | {?s: <[5]} | {?s: <[6]} | {?s: <[7]} |\n", .{
            a.labels.instance,
            a.state,
            a.labels.alertname,
            a.annotations.description,
            max_lengths[0],
            max_lengths[1],
            max_lengths[2],
            max_lengths[3],
        });
    }

    // TODO print: Instance, State, Alert, Description
}
const Alerts = struct {
    status: []u8,
    data: struct {
        alerts: []struct {
            // TODO Labels should be optional
            labels: struct {
                alertname: []u8,
                device: ?[]u8 = null,
                fstype: ?[]u8 = null,
                instance: []u8,
                job: []u8,
                mountpoint: ?[]u8 = null,
            },
            // TODO Annotations should be optional
            annotations: struct {
                description: []u8,
            },
            state: []u8 = "",
            activeAt: ?[]u8 = null,
            value: ?[]u8 = null,
        },
    },
};

fn getJSON(url: []const u8) ![]u8 {
    var client = std.http.Client{
        .allocator = allocator,
    };

    // we can `catch unreachable` here because we can guarantee that this is a valid url.
    const uri = try std.Uri.parse(url);

    // these are the headers we'll be sending to the server
    var headers = std.http.Headers{ .allocator = allocator };
    defer headers.deinit();

    try headers.append("accept", "*/*"); // tell the server we'll accept anything

    // make the connection and set up the request
    var req = try client.request(.GET, uri, headers, .{});
    defer req.deinit();

    // I'm making a GET request, so do I don't need this, but I'm sure someone will.
    // req.transfer_encoding = .chunked;

    // send the request and headers to the server.
    try req.start();

    // try req.writer().writeAll("Hello, World!\n");
    // try req.finish();

    // wait for the server to send use a response
    try req.wait();

    // read the content-type header from the server, or default to text/plain
    const content_type = req.response.headers.getFirstValue("content-type") orelse "text/plain";
    _ = content_type;

    // read the entire response body, but only allow it to allocate 100kb of memory
    const body = try req.reader().readAllAlloc(allocator, 102400);

    print("Body was {s}\n", .{body});

    defer allocator.free(body);

    return body;
}

// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }

const test_json =
    \\{
    \\  "status": "success",
    \\  "data": {
    \\    "alerts": [
    \\      {
    \\        "labels": {
    \\          "alertname": "filesystem_full_80percent",
    \\          "device": "/dev/disk/by-uuid/e9d0b6a6-e7e8-4933-9cb1-b0829ede77ff",
    \\          "fstype": "ext4",
    \\          "instance": "ahorn.wireguard:9100",
    \\          "job": "node-stats",
    \\          "mountpoint": "/"
    \\        },
    \\        "annotations": {
    \\          "description": "ahorn.wireguard:9100 device /dev/disk/by-uuid/e9d0b6a6-e7e8-4933-9cb1-b0829ede77ff on / got less than 20% space left on its filesystem."
    \\        },
    \\        "state": "firing",
    \\        "activeAt": "2023-08-31T10:40:49.507719931Z",
    \\        "value": "8.709753578136561e+01"
    \\      },
    \\      {
    \\        "labels": {
    \\          "alertname": "host_down",
    \\          "instance": "bob.wireguard:9100",
    \\          "job": "node-stats"
    \\        },
    \\        "annotations": {
    \\          "description": "bob.wireguard:9100 is down!"
    \\        },
    \\        "state": "firing",
    \\        "activeAt": "2023-08-31T08:35:49.507719931Z",
    \\        "value": "0e+00"
    \\      },
    \\      {
    \\        "labels": {
    \\          "alertname": "http_status",
    \\          "instance": "https://build.lounge.rocks",
    \\          "job": "blackbox"
    \\        },
    \\        "annotations": {
    \\          "description": "http request failed from https://build.lounge.rocks: !"
    \\        },
    \\        "state": "firing",
    \\        "activeAt": "2023-08-31T08:35:49.507719931Z",
    \\        "value": "4.03e+02"
    \\      },
    \\      {
    \\        "labels": {
    \\          "alertname": "swap_using_20percent",
    \\          "instance": "ahorn.wireguard:9100",
    \\          "job": "node-stats"
    \\        },
    \\        "annotations": {
    \\          "description": "ahorn.wireguard:9100 is using 20% of its swap space for at least 30 minutes."
    \\        },
    \\        "state": "firing",
    \\        "activeAt": "2023-08-31T10:40:49.507719931Z",
    \\        "value": "2.414403584e+09"
    \\      },
    \\      {
    \\        "labels": {
    \\          "alertname": "systemd_service_failed",
    \\          "instance": "ahorn.wireguard:9100",
    \\          "job": "node-stats",
    \\          "name": "borgbackup-job-box-backup.service",
    \\          "state": "failed",
    \\          "type": "simple"
    \\        },
    \\        "annotations": {
    \\          "description": "ahorn.wireguard:9100 failed to (re)start service borgbackup-job-box-backup.service."
    \\        },
    \\        "state": "firing",
    \\        "activeAt": "2023-08-31T10:40:49.507719931Z",
    \\        "value": "1e+00"
    \\      },
    \\      {
    \\        "labels": {
    \\          "alertname": "uptime",
    \\          "instance": "birne.wireguard:9100",
    \\          "job": "node-stats"
    \\        },
    \\        "annotations": {
    \\          "description": "Uptime monster: birne.wireguard:9100 has been up for more than 30 days."
    \\        },
    \\        "state": "firing",
    \\        "activeAt": "2023-08-31T08:35:49.507719931Z",
    \\        "value": "3.1220607719907054e+01"
    \\      },
    \\      {
    \\        "labels": {
    \\          "alertname": "uptime",
    \\          "instance": "porree.wireguard:9100",
    \\          "job": "node-stats"
    \\        },
    \\        "annotations": {
    \\          "description": "Uptime monster: porree.wireguard:9100 has been up for more than 30 days."
    \\        },
    \\        "state": "firing",
    \\        "activeAt": "2023-08-31T08:35:49.507719931Z",
    \\        "value": "3.6230607719907056e+01"
    \\      }
    \\    ]
    \\  }
    \\}
;
