const std = @import("std");

pub const TipoPlanta = enum {
    arbol,
    arbusto,
};

pub const TipoEvento = enum {
    riego,
    poda,
    fertilizante,
    plaga,
    otro,
};

pub const EventoCuidado = struct {
    fecha: []const u8,                    // Por ahora usamos string "2025-06-06"
    tipo: TipoEvento,
    cantidad_litros: ?u32 = null,
    notas: ?[]const u8 = null,
};

pub const Planta = struct {
    id: []const u8,
    tipo: TipoPlanta,
    nombre_comun: []const u8,
    especie: ?[]const u8 = null,            // this is equivalent to a Option<String> in rust
    nativo: bool = false,
    zona_ubicacion: []const u8,
    fecha_plantado: ?[]const u8 = null,
    altura_actual_cm: ?u32 = null,
    notas: ?[]const u8 = null,
    urls_documentacion: []const []const u8 = &.{},
    bitacora: []EventoCuidado = &.{},
};

pub fn handleAdd(io: std.Io, iter: anytype, allocator: std.mem.Allocator) !void {
    // 1. Obtener el tipo:
    const tipo_str = iter.next() orelse {
        std.debug.print("Error: falta el tipo (arbol|arbusto)\n", .{});
        return;
    };

    // 2. Obtener nombre (obligatorio)
    const nombre = iter.next() orelse {
        std.debug.print("Error: falta el nombre de la planta\n", .{});
        return;
    };

    // 3. Variables para los campos opcionales
    var zona: []const u8 = "Sin zona especificada";
    var altura: ?u32 = null;
    var nativo: bool = false;
    var notas: ?[]const u8 = null;
    var especie: ?[]const u8 = null;

    // 4. Parsear opciones (--zona, --altura, --nativo, etc.)
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--zona")) {
            zona = iter.next() orelse {
                std.debug.print("Error: --zona requiere un valor\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--altura")) {
            const altura_str = iter.next() orelse {
                std.debug.print("Error: --altura requiere un valor\n", .{});
                return;
            };
            altura = std.fmt.parseInt(u32, altura_str, 10) catch {
                std.debug.print("Error: --altura debe ser un número\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--nativo")) {
            nativo = true;
        } else if (std.mem.eql(u8, arg, "--notas")) {
            notas = iter.next() orelse {
                std.debug.print("Error: --notas requiere un valor\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--especie")) {
            especie = iter.next() orelse {
                std.debug.print("Error: --especie requiere un valor\n", .{});
                return;
            };
        } else {
            std.debug.print("Opción desconocida: {s}\n", .{arg});
        }
    }

    // 5. Crear la planta (por ahora solo la imprimimos)
    std.debug.print("=== Nueva Planta ===\n", .{});
    std.debug.print("Tipo: {s}\n", .{tipo_str});
    std.debug.print("Nombre: {s}\n", .{nombre});
    std.debug.print("Zona: {s}\n", .{zona});
    std.debug.print("Altura: {?}\n", .{altura});
    std.debug.print("Nativo: {}\n", .{nativo});

    if (especie) |e| {
        std.debug.print("Especie: {s}\n", .{e});
    }

    if (notas) |n| {
        std.debug.print("Notas: {s}\n", .{n});
    }

    const ts = std.Io.Clock.real.now(io);
    const timestamp: i64 = @intCast(@divTrunc(ts.nanoseconds, std.time.ns_per_s));
    const id = try std.fmt.allocPrint(allocator, "planta-{d}", .{timestamp});
    defer allocator.free(id);

    const planta = Planta{
        .id = id,
        .tipo = if (std.mem.eql(u8, tipo_str, "arbol")) .arbol else .arbusto,
        .nombre_comun = nombre,
        .especie = especie,
        .nativo = nativo,
        .zona_ubicacion = zona,
        .altura_actual_cm = altura,
        .notas = notas,
    };

    try guardarPlanta(planta, io, allocator);
}

fn guardarPlanta(nueva_planta: Planta, io: std.Io, allocator: std.mem.Allocator) !void {
    const path = "plants.json";

    // 1. Leer plantas existentes (si el archivo existe)
    var plantas: std.ArrayList(Planta) = .empty;
    defer plantas.deinit(allocator);

    // contenido y parsed viven hasta el final de la función para que los strings
    // dentro de `plantas` (punteros al buffer JSON) sigan siendo válidos durante
    // la serialización posterior.
    var contenido: ?[]u8 = null;
    defer if (contenido) |c| allocator.free(c);
    var parsed: ?std.json.Parsed([]Planta) = null;
    defer if (parsed) |*p| p.deinit();

    if (std.Io.Dir.cwd().access(io, path, .{})) {
        contenido = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
        parsed = try std.json.parseFromSlice([]Planta, allocator, contenido.?, .{});
        try plantas.appendSlice(allocator, parsed.?.value);
    } else |_| {
        std.debug.print("File does not exist ..., starting from scratch.\n", .{});
    }

    // 2. Agregar la nueva planta
    try plantas.append(allocator, nueva_planta);

    // 3. Convertir a JSON y guardar
    const archivo = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer archivo.close(io);

    var buffer: [4096]u8 = undefined;
    var fw = archivo.writer(io, &buffer);
    try std.json.Stringify.value(plantas.items, .{ .whitespace = .indent_2 }, &fw.interface);
    try fw.interface.flush();

    std.debug.print("Planta guardada exitosamente en {s}\n", .{path});
}

pub fn handleList(io: std.Io, allocator: std.mem.Allocator) !void {
    const path = "plants.json";
    if (std.Io.Dir.cwd().access(io, path, .{})) {
        const contenido = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
        defer allocator.free(contenido);

        const parsed = try std.json.parseFromSlice([]Planta, allocator, contenido, .{});
        defer parsed.deinit();

        const plantas = parsed.value;

        if (plantas.len == 0) {
            std.debug.print("No hay plantas o árboles registrados.\n", .{});
            return;
        }

        std.debug.print("\n=== Lista de plantas ({d}) ===\n", .{plantas.len});

        for (plantas, 0..) |plant, i| {
            std.debug.print("{d} {s}\n", .{ i + 1, plant.nombre_comun });
            std.debug.print("    ID:     {s}\n", .{ plant.id });
            std.debug.print("    Tipo:    {s}\n", .{ @tagName(plant.tipo) });
            std.debug.print("    Zona:    {s}\n", .{ plant.zona_ubicacion });

            if (plant.especie) |esp| {
                std.debug.print("     Especie: {s}\n", .{ esp });
            }

            if (plant.altura_actual_cm) |h| {
                std.debug.print("    Altura: {d} cm\n", .{ h });
            }

            std.debug.print("    Nativo: {s}\n", .{ if (plant.nativo) "Sí" else "No" });

            if (plant.notas) |n| {
                std.debug.print("    Notas: {s}\n", .{ n });
            }

            std.debug.print("    Eventos en bitácora: {d}\n", .{ plant.bitacora.len });
            std.debug.print("\n", .{});
        }
    } else |_| {
        std.debug.print("DB file might not be ready.", .{});
    }
}
