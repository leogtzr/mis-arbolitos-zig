const std = @import("std");
const plants = @import("plants.zig");

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdoutBuff: [1024]u8 = undefined;
    var stderrBuff: [1024]u8 = undefined;

    const io = init.io;

    var stdoutFw = std.Io.File.stdout().writer(io, &stdoutBuff);
    var stderrFw = std.Io.File.stderr().writer(io, &stderrBuff);

    // Some aliases:
    const stdout = &stdoutFw.interface;
    const stderr = &stderrFw.interface;

    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var iter = init.minimal.args.iterate();
    _ = iter.skip();            // Saltamos el nombre del ejecutable.

    const comando = iter.next() orelse {
        try stderr.print("Uso: mis-arbolitos-zig <comando> [opciones]\n", .{});
        return;
    };

    if (std.mem.eql(u8, comando, "add")) {
        try plants.handleAdd(init.io, &iter, allocator, stdout, stderr);
    } else if (std.mem.eql(u8, comando, "list")) {
        try plants.handleList(init.io, allocator, stdout, stderr);
    } else if (std.mem.eql(u8, comando, "show")) {
        try plants.handleShowPlantById(init.io, &iter, allocator, stdout, stderr);
    } else if (std.mem.eql(u8, comando, "log")) {
        try plants.handleLog(init.io, &iter, allocator, stdout, stderr);
    } else if (std.mem.eql(u8, comando, "edit")) {
        try plants.handleEdit(init.io, &iter, allocator, stdout, stderr);
    } else {
        try stderr.print("Comando desconocido: {s}\n", .{comando});
    }
}
