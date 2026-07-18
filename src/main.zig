const std = @import("std");
const Io = std.Io;

const Project = struct { name: []const u8, local: []const u8, tags: []const []const u8 = &.{}, shared: bool = false };
const State = struct { root: []const u8, active: ?[]const u8, projects: []Project };

fn readFile(a: std.mem.Allocator, io: Io, p: []const u8) ![]u8 {
    const f = try Io.Dir.openFileAbsolute(io, p, .{});
    defer f.close(io);
    const size: usize = @intCast((try f.stat(io)).size);
    if (size > 1024 * 1024) return error.FileTooLarge;
    const buf = try a.alloc(u8, size);
    errdefer a.free(buf);
    var r = f.reader(io, &.{});
    const n = r.interface.readSliceShort(buf) catch |e| switch (e) { error.ReadFailed => return r.err.? };
    return buf[0..n];
}

fn exists(io: Io, path: []const u8) bool {
    _ = Io.Dir.openFileAbsolute(io, path, .{}) catch return false;
    return true;
}

fn readState(a: std.mem.Allocator, io: Io, p: []const u8) !State {
    return try std.json.parseFromSliceLeaky(State, a, (try readFile(a, io, p)), .{ .allocate = .alloc_always });
}

fn writeState(a: std.mem.Allocator, io: Io, s: State, p: []const u8) !void {
    if (std.fs.path.dirname(p)) |d| Io.Dir.createDirPath(Io.Dir.cwd(), io, d) catch {};
    var j: std.ArrayList(u8) = .empty;
    try j.appendSlice(a, "{\"root\":\"");
    try j.appendSlice(a, s.root);
    try j.appendSlice(a, "\",\"active\":");
    if (s.active) |x| { try j.append(a, '"'); try j.appendSlice(a, x); try j.append(a, '"'); }
    else try j.appendSlice(a, "null");
    try j.appendSlice(a, ",\"projects\":[");
    for (s.projects, 0..) |pj, i| {
        if (i > 0) try j.append(a, ',');
        try j.appendSlice(a, "{\"name\":\"");
        try j.appendSlice(a, pj.name);
        try j.appendSlice(a, "\",\"local\":\"");
        try j.appendSlice(a, pj.local);
        try j.appendSlice(a, "\",\"tags\":[");
        for (pj.tags, 0..) |tg, ti| {
            if (ti > 0) try j.append(a, ',');
            try j.append(a, '"');
            try j.appendSlice(a, tg);
            try j.append(a, '"');
        }
        try j.appendSlice(a, "]");
        if (pj.shared) try j.appendSlice(a, ",\"shared\":true") else try j.appendSlice(a, "");
        try j.appendSlice(a, "}");
    }
    try j.appendSlice(a, "]}");
    const f = try Io.Dir.createFileAbsolute(io, p, .{});
    defer f.close(io);
    var w = f.writer(io, &.{});
    try w.interface.writeAll(j.items);
    try w.interface.flush();
}

fn readLine(a: std.mem.Allocator, io: Io) ![]const u8 {
    var rbuf: [256]u8 = undefined;
    var rd: Io.File.Reader = .init(.stdin(), io, &rbuf);
    const r = &rd.interface;
    var buf: std.ArrayList(u8) = .empty;
    while (true) {
        var b: [1]u8 = undefined;
        const n = r.readSliceShort(&b) catch break;
        if (n == 0) break;
        if (b[0] == '\n' or b[0] == '\r') break;
        try buf.append(a, b[0]);
    }
    return buf.items;
}

fn prompt(a: std.mem.Allocator, io: Io, home: []const u8) !State {
    var sbuf: [256]u8 = undefined;
    var sw: Io.File.Writer = .init(.stderr(), io, &sbuf);
    const d = try std.fs.path.join(a, &.{ home, "Documents", "WorkSpace" });
    try sw.interface.print("Welcome to wksp!\nEnter workspace root directory [{s}]: ", .{d});
    try sw.interface.flush();
    const t = std.mem.trim(u8, (readLine(a, io) catch ""), " \t");
    return .{ .root = if (t.len == 0) d else if (std.fs.path.isAbsolute(t)) t else try std.fs.path.join(a, &.{ home, t }), .active = null, .projects = &.{} };
}

fn absPath(a: std.mem.Allocator, io: Io, raw: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(raw)) return raw;
    return std.fs.path.join(a, &.{ try std.process.currentPathAlloc(io, a), raw });
}

fn ensureRoot(io: Io, root: []const u8) !void {
    try Io.Dir.createDirPath(Io.Dir.cwd(), io, root);
    const t = try std.fs.path.join(std.heap.page_allocator, &.{ root, "targets" });
    defer std.heap.page_allocator.free(t);
    try Io.Dir.createDirPath(Io.Dir.cwd(), io, t);
}

fn removeDir(io: Io, path: []const u8) void {
    if (Io.Dir.openDirAbsolute(io, path, .{})) |d| {
        var it = d.iterate();
        while (true) {
            const entry = it.next(io) catch break;
            if (entry) |e| switch (e.kind) {
                .sym_link, .file => Io.Dir.deleteFile(d, io, e.name) catch {},
                .directory => {
                    const sub = std.fs.path.join(std.heap.page_allocator, &.{ path, e.name }) catch continue;
                    defer std.heap.page_allocator.free(sub);
                    removeDir(io, sub);
                },
                else => {},
            } else break;
        }
        d.close(io);
        if (std.fs.path.dirname(path)) |parent| {
            if (Io.Dir.openDirAbsolute(io, parent, .{})) |pd| {
                const nm = std.fs.path.basename(path);
                if (nm.len > 0 and !std.mem.eql(u8, nm, ".")) Io.Dir.deleteDir(pd, io, nm) catch {};
                pd.close(io);
            } else |_| {}
        }
    } else |_| {}
}

fn mkParent(io: Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |d| if (d.len > 0) Io.Dir.createDirPath(Io.Dir.cwd(), io, d) catch {};
}

fn pr(s: State, name: []const u8) ?*const Project {
    for (s.projects) |*p| if (std.mem.eql(u8, p.name, name)) return p;
    return null;
}

fn setProject(a: std.mem.Allocator, s: *State, name: []const u8, local: []const u8, tags: []const []const u8, shared: bool) !void {
    for (s.projects, 0..) |p, i| {
        if (std.mem.eql(u8, p.name, name)) { s.projects[i].local = local; s.projects[i].tags = tags; s.projects[i].shared = shared; return; }
    }
    const list = try a.alloc(Project, s.projects.len + 1);
    @memcpy(list[0..s.projects.len], s.projects);
    list[s.projects.len] = .{ .name = name, .local = local, .tags = tags, .shared = shared };
    s.projects = list;
}

fn projShared(s: State, name: []const u8) bool {
    if (pr(s, name)) |p| return p.shared;
    return false;
}

fn isProject(s: State, name: []const u8) bool {
    return pr(s, name) != null;
}

fn removeEmptyDir(io: Io, path: []const u8) void {
    var d = Io.Dir.openDirAbsolute(io, path, .{}) catch return;
    defer d.close(io);
    var it = d.iterate();
    if ((it.next(io) catch null) != null) return; // not empty
    d.close(io);
    if (std.fs.path.dirname(path)) |parent| {
        if (Io.Dir.openDirAbsolute(io, parent, .{})) |pd| {
            Io.Dir.deleteDir(pd, io, std.fs.path.basename(path)) catch {};
            pd.close(io);
        } else |_| {}
    }
}

fn linkTag(io: Io, root: []const u8, tag: []const u8, name: []const u8, base: []const u8, s: State) !void {
    const real = try std.fs.path.join(std.heap.page_allocator, &.{ root, tag, name });
    defer std.heap.page_allocator.free(real);
    Io.Dir.createDirPath(Io.Dir.cwd(), io, real) catch {};

    const local = try std.fs.path.join(std.heap.page_allocator, &.{ base, tag });
    defer std.heap.page_allocator.free(local);
    Io.Dir.deleteFileAbsolute(io, local) catch {};
    removeDir(io, local);

    // collect shared projects under this tag from state
    var shared: std.ArrayList([]const u8) = .empty;
    for (s.projects) |p| {
        if (!p.shared) continue;
        if (std.mem.eql(u8, p.name, name)) continue;
        for (p.tags) |t| {
            if (std.mem.eql(u8, t, tag)) {
                try shared.append(std.heap.page_allocator, p.name);
                break;
            }
        }
    }
    // also link non-project directories under this tag
    const tag_dir = try std.fs.path.join(std.heap.page_allocator, &.{ root, tag });
    defer std.heap.page_allocator.free(tag_dir);
    if (Io.Dir.openDirAbsolute(io, tag_dir, .{})) |td_| {
        defer td_.close(io);
        var ti_ = td_.iterate();
        while (try ti_.next(io)) |e2| {
            if (e2.kind != .directory) continue;
            if (std.mem.eql(u8, e2.name, name)) continue; // skip self
            if (isProject(s, e2.name)) continue; // skip registered projects
            // check if already in shared list
            var dup = false;
            for (shared.items) |x| { if (std.mem.eql(u8, x, e2.name)) { dup = true; break; } }
            if (!dup) try shared.append(std.heap.page_allocator, e2.name);
        }
    } else |_| {}

    if (shared.items.len > 0 or std.fs.path.dirname(tag) != null) {
        // create local/<tag>/ as dir with symlinks
        try mkParent(io, local);
        Io.Dir.createDirPath(Io.Dir.cwd(), io, local) catch {};
        var ld = try Io.Dir.openDirAbsolute(io, local, .{});
        defer ld.close(io);
        try ld.symLink(io, real, "self", .{});
        for (shared.items) |sn| {
            const sr = try std.fs.path.join(std.heap.page_allocator, &.{ root, tag, sn });
            defer std.heap.page_allocator.free(sr);
            try ld.symLink(io, sr, sn, .{});
        }
    } else {
        try mkParent(io, local);
        var d = try Io.Dir.openDirAbsolute(io, base, .{});
        defer d.close(io);
        try d.symLink(io, real, tag, .{});
    }
}

fn listProjects(a: std.mem.Allocator, io: Io, s: State) !void {
    var sbuf: [256]u8 = undefined;
    var sw: Io.File.Writer = .init(.stderr(), io, &sbuf);
    const o = &sw.interface;
    _ = a;

    if (s.projects.len == 0) { try o.print("(empty)\n", .{}); try o.flush(); return; }

    for (s.projects) |p| {
        const m: []const u8 = if (s.active != null and std.mem.eql(u8, s.active.?, p.name)) "*" else " ";
        const sh = if (p.shared) " [shared]" else "";
        try o.print("{s}{s}  {s}{s}\n", .{ m, p.name, p.local, sh });
    }
    try o.flush();
}

fn listTags(a: std.mem.Allocator, io: Io, root: []const u8) !void {
    var sbuf: [256]u8 = undefined;
    var sw: Io.File.Writer = .init(.stderr(), io, &sbuf);
    const o = &sw.interface;
    var dirs: std.ArrayList([]const u8) = .empty;
    var rd = Io.Dir.openDirAbsolute(io, root, .{}) catch return;
    defer rd.close(io);
    var ri = rd.iterate();
    while (try ri.next(io)) |e| {
        if (e.kind != .directory or std.mem.eql(u8, e.name, "workspace")) continue;
        try dirs.append(a, e.name);
    }
    for (dirs.items) |d| try o.print("{s}\n", .{d});
    try o.flush();
}

fn tagProjects(a: std.mem.Allocator, io: Io, s: State, tag: []const u8) !void {
    var sbuf: [256]u8 = undefined;
    var sw: Io.File.Writer = .init(.stderr(), io, &sbuf);
    const o = &sw.interface;
    _ = a;
    var empty = true;
    for (s.projects) |p| {
        for (p.tags) |t| {
            if (std.mem.eql(u8, t, tag)) { try o.print("{s}\n", .{p.name}); empty = false; break; }
        }
    }
    if (empty) try o.print("(empty)\n", .{});
    try o.flush();
}

fn tagDelete(io: Io, root: []const u8, tag: []const u8) !void {
    const td = try std.fs.path.join(std.heap.page_allocator, &.{ root, tag });
    defer std.heap.page_allocator.free(td);
    var d = Io.Dir.openDirAbsolute(io, td, .{}) catch return;
    var it = d.iterate();
    while (try it.next(io)) |e| if (e.kind == .directory) return; // not empty
    d.close(io);
    removeDir(io, td);
}

fn projectTags(a: std.mem.Allocator, io: Io, s: State, proj: []const u8) !void {
    var sbuf: [256]u8 = undefined;
    var sw: Io.File.Writer = .init(.stderr(), io, &sbuf);
    const o = &sw.interface;
    _ = a;
    if (pr(s, proj)) |p| {
        for (p.tags) |t| try o.print("{s}\n", .{t});
        if (p.tags.len == 0) try o.print("targets\n", .{});
    } else {
        try o.print("(none)\n", .{});
    }
    try o.flush();
}

fn prefixMatch(cmd: []const u8, known: []const []const u8) bool {
    for (known) |k| if (std.mem.startsWith(u8, k, cmd) and !std.mem.eql(u8, k, cmd)) return true;
    return false;
}

fn printUsage(io: Io) void {
    var sbuf: [256]u8 = undefined;
    var sw: Io.File.Writer = .init(.stderr(), io, &sbuf);
    sw.interface.print(
        \\wksp
        \\
        \\  wksp                     list projects
        \\  wksp <name> [@tag,...]   register cwd as project (default: targets)
        \\  wksp <name> -k [...]     register, keep existing local dirs
        \\  wksp <name> -l           list tags for project
        \\  wksp <name> -s           mark project as shared
        \\  wksp <name> -rs          unmark shared
        \\  wksp tag                 list all tags
        \\  wksp tag <name,...>      create tags, list projects if exists
        \\  wksp tag <name> -d       delete empty tag
        \\  wksp clean               clear all projects
        \\  wksp path [<dir>]        show/set root
        \\
    , .{}) catch {};
}

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    const home = init.environ_map.get("HOME") orelse return error.HomeNotSet;
    const cfg = try std.fs.path.join(a, &.{ home, ".config", "wksp", "state.json" });

    var s: State = undefined;
    if (!exists(io, cfg)) {
        if (args.len >= 3 and std.mem.eql(u8, args[1], "path")) {
            s = .{ .root = try absPath(a, io, args[2]), .active = null, .projects = &.{} };
            try ensureRoot(io, s.root);
            try writeState(a, io, s, cfg);
            return;
        }
        s = try prompt(a, io, home);
        try ensureRoot(io, s.root);
        try writeState(a, io, s, cfg);
    } else {
        s = readState(a, io, cfg) catch |e| { std.debug.print("Error: {}\n", .{e}); return e; };
    }

    if (args.len <= 1) { try ensureRoot(io, s.root); try listProjects(a, io, s); return; }

    const cmd = args[1];

    // ---- path ----
    if (std.mem.eql(u8, cmd, "path")) {
        if (args.len == 2) {
            var sbuf: [256]u8 = undefined;
            var sw: Io.File.Writer = .init(.stderr(), io, &sbuf);
            try sw.interface.print("Root: {s}\n", .{s.root});
            if (s.active) |a2| try sw.interface.print("Active: {s}\n", .{a2});
            try sw.interface.flush();
        } else {
            s.root = try absPath(a, io, args[2]);
            s.active = null;
            s.projects = &.{};
            try ensureRoot(io, s.root);
            try writeState(a, io, s, cfg);
        }
        return;
    }

    // ---- list ----
    if (std.mem.eql(u8, cmd, "list")) { try ensureRoot(io, s.root); try listProjects(a, io, s); return; }

    // ---- clean ----
    if (std.mem.eql(u8, cmd, "clean")) {
        for (s.projects) |p| {
            removeDir(io, p.local);
            if (!p.shared) {
                for (p.tags) |t| {
                    const pd = std.fs.path.join(std.heap.page_allocator, &.{ s.root, t, p.name }) catch continue;
                    defer std.heap.page_allocator.free(pd);
                    removeEmptyDir(io, pd);
                }
            }
        }
        s.active = null;
        try writeState(a, io, s, cfg);
        return;
    }

    // ---- tag ----
    if (std.mem.eql(u8, cmd, "tag")) {
        if (args.len == 2) { try listTags(a, io, s.root); return; }
        if (args.len >= 4 and std.mem.eql(u8, args[3], "-d")) {
            var it = std.mem.splitScalar(u8, args[2], ',');
            while (it.next()) |tn| if (tn.len > 0) try tagDelete(io, s.root, tn);
            return;
        }
        var it = std.mem.splitScalar(u8, args[2], ',');
        while (it.next()) |tn| {
            if (tn.len == 0) continue;
            const td = try std.fs.path.join(a, &.{ s.root, tn });
            if (Io.Dir.openDirAbsolute(io, td, .{})) |d| { d.close(io); try tagProjects(a, io, s, tn); }
            else |_| { try Io.Dir.createDirPath(Io.Dir.cwd(), io, td); }
        }
        return;
    }

    // ---- help ----
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help")) { printUsage(io); return; }

    // ---- project ----
    var keep = false;
    var pi: usize = 1;
    if (args.len > 2 and std.mem.eql(u8, cmd, "-k")) { keep = true; pi = 2; }

    if (pi >= args.len) return;
    const proj_cmd = args[pi];
    if (std.mem.indexOfAny(u8, proj_cmd, "/\\") != null) return error.InvalidArgument;

    // parse flags and @tags from remaining args
    var tags: std.ArrayList([]const u8) = .empty;
    var is_shared = projShared(s, proj_cmd); // keep existing shared status
    if (args.len > pi + 1) {
        for (args[pi + 1 ..]) |arg| {
            if (std.mem.eql(u8, arg, "-s")) { is_shared = true; continue; }
            if (std.mem.eql(u8, arg, "-rs")) { is_shared = false; continue; }
            if (std.mem.eql(u8, arg, "-l")) { try projectTags(a, io, s, proj_cmd); return; }
            if (std.mem.startsWith(u8, arg, "@")) {
                var it = std.mem.splitScalar(u8, arg[1..], ',');
                while (it.next()) |t| if (t.len > 0 and !std.mem.eql(u8, t, "list") and !std.mem.eql(u8, t, "help")) try tags.append(a, t);
            }
        }
    }

    try ensureRoot(io, s.root);
    const cwd = try std.process.currentPathAlloc(io, a);
    const base = try std.fs.path.join(a, &.{ cwd, proj_cmd });
    Io.Dir.createDirPath(Io.Dir.cwd(), io, base) catch {};

    if (!keep) {
        for (s.projects) |p| {
            if (std.mem.eql(u8, p.name, proj_cmd)) continue;
            if (!p.shared) {
                for (p.tags) |t| {
                    const pd = std.fs.path.join(std.heap.page_allocator, &.{ s.root, t, p.name }) catch continue;
                    defer std.heap.page_allocator.free(pd);
                    removeEmptyDir(io, pd);
                }
            }
            removeDir(io, p.local);
        }
    }

    if (!is_shared) {
        try linkTag(io, s.root, "targets", proj_cmd, base, s);
        if (tags.items.len == 0) {
            if (pr(s, proj_cmd)) |existing| {
                tags = .{ .items = @constCast(existing.tags), .capacity = existing.tags.len };
            } else {
                var all_tags = try a.alloc([]const u8, 1);
                all_tags[0] = "targets";
                tags = .{ .items = all_tags, .capacity = 1 };
            }
        } else {
            var all_tags = try a.alloc([]const u8, tags.items.len + 1);
            all_tags[0] = "targets";
            @memcpy(all_tags[1..], tags.items);
            tags = .{ .items = all_tags, .capacity = all_tags.len };
        }
    }

    // link non-targets tags
    for (tags.items) |tk| if (!std.mem.eql(u8, tk, "targets")) try linkTag(io, s.root, tk, proj_cmd, base, s);

    try setProject(a, &s, proj_cmd, base, tags.items, is_shared);
    s.active = proj_cmd;
    try writeState(a, io, s, cfg);
}
