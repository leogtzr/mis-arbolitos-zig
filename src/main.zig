const std = @import("std");
const plants = @import("plants.zig");

// pub fn main(init: std.process.Init.Minimal) !void {
//     var iter = init.args.iterate();
//     _ = iter.skip(); // skip executable name
//
//     const comando = iter.next() orelse {
//         std.debug.print("Uso: mis-arbolitos-zig <comando> [opciones]\n", .{});
//         return;
//     };
//
//     if (std.mem.eql(u8, comando, "add")) {
//         std.debug.print("Comando 'add' detectado. (Implementaremos la lógica pronto)\n", .{});
//     } else if (std.mem.eql(u8, comando, "list")) {
//         std.debug.print("Comando 'list' detectado.\n", .{});
//     } else {
//         std.debug.print("Comando desconocido: {s}\n", .{comando});
//     }
// }
//
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var iter = init.minimal.args.iterate();
    _ = iter.skip();            // Saltamos el nombre del ejecutable.

    const comando = iter.next() orelse {
        std.debug.print("Uso: mis-arbolitos-zig <comando> [opciones]\n", .{});
        return;
    };

    if (std.mem.eql(u8, comando, "add")) {
        try plants.handleAdd(init.io, &iter, allocator);
    } else if (std.mem.eql(u8, comando, "list")) {
        try plants.handleList(init.io, allocator);
    } else {
        std.debug.print("Comando desconocido: {s}\n", .{comando});
    }
}
