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
    fecha: []const u8, // Por ahora usamos string "2025-06-06"
    tipo: TipoEvento,
    cantidadLitros: ?u32 = null,
    notas: ?[]const u8 = null,
};

pub const Planta = struct {
    id: []const u8,
    tipo: TipoPlanta,
    nombreComun: []const u8,
    especie: ?[]const u8 = null, // this is equivalent to a Option<String> in rust
    nativo: bool = false,
    zonaUbicacion: []const u8,
    fechaPlantado: ?[]const u8 = null,
    alturaActualCm: ?u32 = null,
    notas: ?[]const u8 = null,
    urlsDocumentacion: []const []const u8 = &.{},
    bitacora: []EventoCuidado = &.{},
};

pub fn handleAdd(
    io: std.Io, 
    iter: anytype, 
    allocator: std.mem.Allocator, 
    stdout: *std.Io.Writer, 
    stderr: *std.Io.Writer
    ) !void {
    // 1. Obtener el tipo:
    const tipoStr = iter.next() orelse {
        try stderr.print("Error: falta el tipo (arbol|arbusto)\n", .{});
        return;
    };

    // 2. Obtener nombre (obligatorio)
    const nombre = iter.next() orelse {
        try stderr.print("Error: falta el nombre de la planta\n", .{});
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
                try stderr.print("Error: --zona requiere un valor\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--altura")) {
            const alturaStr = iter.next() orelse {
                try stderr.print("Error: --altura requiere un valor\n", .{});
                return;
            };
            altura = std.fmt.parseInt(u32, alturaStr, 10) catch {
                try stderr.print("Error: --altura debe ser un número\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--nativo")) {
            nativo = true;
        } else if (std.mem.eql(u8, arg, "--notas")) {
            notas = iter.next() orelse {
                try stderr.print("Error: --notas requiere un valor\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--especie")) {
            especie = iter.next() orelse {
                try stderr.print("Error: --especie requiere un valor\n", .{});
                return;
            };
        } else {
            try stderr.print("Opción desconocida: {s}\n", .{arg});
        }
    }

    // 5. Crear la planta (por ahora solo la imprimimos)
    try stdout.print("=== Nueva Planta ===\n", .{});
    try stdout.print("Tipo: {s}\n", .{tipoStr});
    try stdout.print("Nombre: {s}\n", .{nombre});
    try stdout.print("Zona: {s}\n", .{zona});
    try stdout.print("Altura: {?}\n", .{altura});
    try stdout.print("Nativo: {}\n", .{nativo});

    if (especie) |e| {
        try stdout.print("Especie: {s}\n", .{e});
    }

    if (notas) |n| {
        try stdout.print("Notas: {s}\n", .{n});
    }

    const ts = std.Io.Clock.real.now(io);
    const timestamp: i64 = @intCast(@divTrunc(ts.nanoseconds, std.time.ns_per_s));
    const id = try std.fmt.allocPrint(allocator, "planta-{d}", .{timestamp});
    defer allocator.free(id);

    const planta = Planta{
        .id = id,
        .tipo = if (std.mem.eql(u8, tipoStr, "arbol")) .arbol else .arbusto,
        .nombreComun = nombre,
        .especie = especie,
        .nativo = nativo,
        .zonaUbicacion = zona,
        .alturaActualCm = altura,
        .notas = notas,
    };

    try guardarPlanta(planta, io, allocator, stdout, stderr);
}

fn guardarPlanta(
    nuevaPlanta: Planta, 
    io: std.Io, 
    allocator: std.mem.Allocator, 
    stdout: *std.Io.Writer, 
    stderr: *std.Io.Writer
    ) !void {
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
        try stderr.print("File does not exist ..., starting from scratch.\n", .{});
    }

    // 2. Agregar la nueva planta
    try plantas.append(allocator, nuevaPlanta);

    // 3. Convertir a JSON y guardar
    const archivo = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer archivo.close(io);

    var buffer: [4096]u8 = undefined;
    var fw = archivo.writer(io, &buffer);
    try std.json.Stringify.value(plantas.items, .{ .whitespace = .indent_2 }, &fw.interface);
    try fw.interface.flush();

    try stdout.print("Planta guardada exitosamente en {s}\n", .{path});
}

pub fn handleList(
    io: std.Io, 
    allocator: std.mem.Allocator, 
    stdout: *std.Io.Writer, 
    stderr: *std.Io.Writer
    ) !void {
    const path = "plants.json";
    if (std.Io.Dir.cwd().access(io, path, .{})) {
        const contenido = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
        defer allocator.free(contenido);

        const parsed = try std.json.parseFromSlice([]Planta, allocator, contenido, .{});
        defer parsed.deinit();

        const plantas = parsed.value;

        if (plantas.len == 0) {
            try stderr.print("No hay plantas o árboles registrados.\n", .{});
            return;
        }

        try stdout.print("\n=== Lista de plantas ({d}) ===\n", .{plantas.len});
        for (plantas) |plant| try printPlant(&plant, stdout); 
    } else |_| {
        try stderr.print("DB file might not be ready.", .{});
    }
}

fn printPlant(plant: *const Planta, stdout: *std.Io.Writer) !void {
    try stdout.print("{s}\n", .{plant.nombreComun});
    try stdout.print("    ID:     {s}\n", .{plant.id});
    try stdout.print("    Tipo:    {s}\n", .{@tagName(plant.tipo)});
    try stdout.print("    Zona:    {s}\n", .{plant.zonaUbicacion});

    if (plant.especie) |esp| {
        try stdout.print("     Especie: {s}\n", .{esp});
    }

    if (plant.alturaActualCm) |h| {
        try stdout.print("    Altura: {d} cm\n", .{h});
    }

    try stdout.print("    Nativo: {s}\n", .{if (plant.nativo) "Sí" else "No"});

    if (plant.notas) |n| {
        try stdout.print("    Notas: {s}\n", .{n});
    }

    try stdout.print("    Eventos en bitácora: {d}\n", .{plant.bitacora.len});
    try stdout.print("\n", .{});
}

fn findPlantById(plants: []const Planta, plantId: []const u8) ?*const Planta {
    for (plants) |*plant| {
        if (std.mem.eql(u8, plant.id, plantId)) return plant;
    }
    return null;
}

pub fn handleShowPlantById(
    io: std.Io, 
    iter: anytype, 
    allocator: std.mem.Allocator, 
    stdout: *std.Io.Writer, 
    stderr: *std.Io.Writer) !void {
    const plantIdStr = iter.next() orelse {
        try stderr.print("Error: el id de la planta|árbol a mostrar\n", .{});
        return;
    };

    const path = "plants.json";
    if (std.Io.Dir.cwd().access(io, path, .{})) {
        const contenido = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
        defer allocator.free(contenido);

        const parsed = try std.json.parseFromSlice([]Planta, allocator, contenido, .{});
        defer parsed.deinit();
        const plantas = parsed.value;

        if (findPlantById(plantas, plantIdStr)) |plant| {
            try printPlant(plant, stdout);
        } else {
            try stderr.print("Planta no encontrada ... :(\n", .{});
        }
    } else |_| {
        try stderr.print("DB file might not be ready.\n", .{});
    }
}
