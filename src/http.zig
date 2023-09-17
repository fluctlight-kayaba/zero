const std = @import("std");
const net = std.net;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const ParsingError = error{
    MethodNotValid,
};

pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    OPTION,
    DELETE,

    pub fn fromString(s: []const u8) !Method {
        if (std.mem.eql(u8, "GET", s)) return .GET;
        if (std.mem.eql(u8, "POST", s)) return .POST;
        if (std.mem.eql(u8, "PUT", s)) return .PUT;
        if (std.mem.eql(u8, "PATCH", s)) return .PATCH;
        if (std.mem.eql(u8, "OPTION", s)) return .OPTION;
        if (std.mem.eql(u8, "DELETE", s)) return .DELETE;

        return ParsingError.MethodNotValid;
    }
};

pub const Version = enum {
    @"1.1",
    @"2",

    pub fn fromString(s: []const u8) !Version {
        if (std.mem.eql(u8, "HTTP/1.1", s)) return .@"1.1";
        if (std.mem.eql(u8, "HTTP/2", s)) return .@"2";

        return ParsingError.MethodNotValid;
    }

    pub fn asString(self: Version) []const u8 {
        if (self == Version.@"1.1") return "HTTP/1.1";
        if (self == Version.@"2") return "HTTP/2";
        unreachable;
    }
};

pub const Status = enum {
    OK,

    pub fn asString(self: Status) []const u8 {
        if (self == Status.OK) return "OK";
    }

    pub fn asNumber(self: Status) usize {
        if (self == Status.OK) return 200;
    }
};

pub const Context = struct {
    method: Method,
    uri: []const u8,
    version: Version,
    headers: std.StringHashMap([]const u8),
    stream: net.Stream,

    pub fn bodyReader(self: *Context) net.Stream.Reader {
        return self.stream.reader();
    }

    pub fn response(self: *Context) net.Stream.Writer {
        return self.stream.writer();
    }

    pub fn respond(self: *Context, status: Status, maybe_headers: ?std.StringHashMap([]const u8), body: []const u8) !void {
        var writer = self.response();
        try writer.print("{s} {} {s}\r\n", .{ self.version.asString(), status.asNumber(), status.asString() });

        if (maybe_headers) |headers| {
            var headers_iter = headers.iterator();
            while (headers_iter.next()) |entry| {
                try writer.print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }

        try writer.print("\r\n", .{});
        _ = try writer.write(body);
    }

    pub fn debugPrintRequest(self: *Context) void {
        print("method: {any}\nuri: {s}\nversion: {any}\n", .{ self.method, self.uri, self.version });

        var headers_iter = self.headers.iterator();
        while (headers_iter.next()) |entry| {
            print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    pub fn init(allocator: Allocator, stream: net.Stream) !Context {
        var first_line = try stream.reader().readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
        first_line = first_line[0 .. first_line.len - 1];
        var first_line_iter = std.mem.split(u8, first_line, " ");

        var headers = std.StringHashMap([]const u8).init(allocator);
        const method = first_line_iter.next().?;
        const uri = first_line_iter.next().?;
        const version = first_line_iter.next().?;

        while (true) {
            var line = try stream.reader().readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
            if (line.len == 1 and std.mem.eql(u8, line, "\r")) break;
            line = line[0..line.len];
            var line_iter = std.mem.split(u8, line, ":");
            const key = line_iter.next().?;
            var value = line_iter.next().?;
            if (value[0] == ' ') value = value[1..];
            try headers.put(key, value);
        }

        return Context{
            .headers = headers,
            .method = try Method.fromString(method),
            .version = try Version.fromString(version),
            .uri = uri,
            .stream = stream,
        };
    }
};

pub const Server = struct {
    config: Config,
    allocator: Allocator,
    address: net.Address,
    stream: net.StreamServer = undefined,
    frames: std.ArrayList(*Connection),

    pub const Config = struct {
        address: []const u8 = "127.0.0.1",
        port: u16 = 3005,
    };

    pub const Connection = struct {
        frame: @Frame(handler),
    };

    pub fn deinit(self: *Server) void {
        self.stream.close();
        self.stream.deinit();
    }

    pub fn init(allocator: Allocator, config: Config) !Server {
        return Server{
            .config = config,
            .allocator = allocator,
            .address = try net.Address.resolveIp(config.address, config.port),
            .frames = std.ArrayList(*Connection).init(allocator),
        };
    }

    fn handler(allocator: Allocator, stream: net.Stream) !void {
        defer stream.close();
        var context = try Context.init(allocator, stream);
        if (std.mem.eql(u8, context.uri, "/sleep")) std.time.sleep(std.time.ns_per_s * 30);
        context.debugPrintRequest();

        try context.respond(Status.OK, null, "Hello from ZIG\n");
    }

    pub fn listen(self: *Server) !*Server {
        self.stream = net.StreamServer.init(.{});
        try self.stream.listen(self.address);

        while (true) {
            const connection = try self.stream.accept();
            var conn = try self.allocator.create(Connection);
            conn.* = .{ .frame = async handler(self.allocator, connection.stream) };
            try self.frames.append(conn);
        }
    }
};
