const std = @import("std");
const http = @import("http.zig");
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const Status = http.Status;

pub fn main() anyerror!void {
    var gpa = GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var handlers = std.ArrayList(http.Handler).init(allocator);
    try handlers.append(home_handler);
    try handlers.append(default_handler);

    var server = try http.Server.init(allocator, .{
        .port = 3005,
        .handlers = handlers.items,
    });

    _ = try server.listen();
}

fn home_predicate(context: *http.Context) anyerror!bool {
    return std.mem.eql(u8, context.uri, "/home");
}

fn home_func(context: *http.Context) anyerror!void {
    try context.respond(http.Status.OK, "Hello from home!", null);
}

const home_handler = http.Handler{
    .predicate = home_predicate,
    .func = home_func,
};

fn default_predicate(_: *http.Context) anyerror!bool {
    return true;
}

fn default_func(context: *http.Context) anyerror!void {
    try context.respond(Status.OK, "Not found!", null);
}

const default_handler = http.Handler{
    .predicate = default_predicate,
    .func = default_func,
};
