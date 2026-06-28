const std = @import("std");
const Regex = @import("regex").Regex;

pub const TipoPlanta = enum {
    arbol,
    arbusto,
    cactacea,
};

pub const TipoEvento = enum {
    riego,
    poda,
    fertilizante,
    plaga,
    otro,
};

pub const EstadoSalud = enum { sana, enferma, recuperacion, muerta };

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
    estado: ?EstadoSalud = null,
};

pub fn handleAdd(io: std.Io, iter: anytype, allocator: std.mem.Allocator, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !void {
    // 1. Obtener el tipo:
    const tipoStr = iter.next() orelse {
        try stderr.print("Error: falta el tipo (arbol|arbusto|cactacea)\n", .{});
        return;
    };

    // 2. Obtener nombre (obligatorio)
    const nombre = iter.next() orelse {
        try stderr.print("Error: falta el nombre de la planta\n", .{});
        return;
    };

    const tipo = std.meta.stringToEnum(TipoPlanta, tipoStr) orelse {
        try stderr.print("Error: tipo inválido: '{s}'. Usa 'arbol', 'arbusto' o 'cactacea'\n", .{tipoStr});
        return;
    };

    // 3. Variables para los campos opcionales
    var zona: []const u8 = "Sin zona especificada";
    var altura: ?u32 = null;
    var nativo: bool = false;
    var notas: ?[]const u8 = null;
    var especie: ?[]const u8 = null;
    var fechaPlantado: ?[]const u8 = null;
    var estado: ?EstadoSalud = null;

    var urls: std.ArrayList([]const u8) = .empty;
    defer urls.deinit(allocator);

    // 4. Parsear opciones (--zona, --altura, --nativo, --estado, etc.)
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
            const nativoStr = iter.next() orelse {
                try stderr.print("Error: --nativo requiere un valor (true|false)\n", .{});
                return;
            };
            if (std.mem.eql(u8, nativoStr, "true")) {
                nativo = true;
            } else if (std.mem.eql(u8, nativoStr, "false")) {
                nativo = false;
            } else {
                try stderr.print("Error: --nativo debe ser 'true' o 'false'\n", .{});
                return;
            }
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
        } else if (std.mem.eql(u8, arg, "--estado")) {
            const estadoSaludStr = iter.next() orelse {
                try stderr.print("Error: --estado requiere un valor\n", .{});
                return;
            };
            estado = std.meta.stringToEnum(EstadoSalud, estadoSaludStr) orelse {
                try stderr.print("Error: estado inválido '{s}'. Usa: sana, enferma, recuperacion o muerta \n", .{estadoSaludStr});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--fecha-plantado")) {
            fechaPlantado = iter.next() orelse {
                try stderr.print("Error: --fecha-plantado requiere un valor.\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--url")) {
            const url = iter.next() orelse {
                try stderr.print("Error: url requiere un valor.\n", .{});
                return;
            };
            try urls.append(allocator, url);
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
    try stdout.print("Estado: {any}\n", .{estado});

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
        .tipo = tipo,
        .nombreComun = nombre,
        .especie = especie,
        .nativo = nativo,
        .zonaUbicacion = zona,
        .alturaActualCm = altura,
        .fechaPlantado = fechaPlantado,
        .urlsDocumentacion = try urls.toOwnedSlice(allocator),
        .notas = notas,
        .estado = estado,
    };

    try guardarPlanta(planta, io, allocator, stdout);
}

fn guardarPlantas(plantasFilePath: []const u8, plantas: std.ArrayList(Planta), io: std.Io) !void {
    const archivo = try std.Io.Dir.cwd().createFile(io, plantasFilePath, .{ .truncate = true });
    defer archivo.close(io);

    var buffer: [4096]u8 = undefined;
    var fw = archivo.writer(io, &buffer);
    try std.json.Stringify.value(plantas.items, .{ .whitespace = .indent_4 }, &fw.interface);
    try fw.interface.flush();
}

fn guardarPlanta(nuevaPlanta: Planta, io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.Writer) !void {
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

    const archivoExiste = if (std.Io.Dir.cwd().access(io, path, .{})) true else |_| false;
    if (archivoExiste) {
        contenido = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
        parsed = try std.json.parseFromSlice([]Planta, allocator, contenido.?, .{});
        try plantas.appendSlice(allocator, parsed.?.value);
    }

    // 2. Agregar la nueva planta
    try plantas.append(allocator, nuevaPlanta);

    // 3. Convertir a JSON y guardar
    try guardarPlantas(path, plantas, io);
    try stdout.print("Planta guardada exitosamente en {s}\n", .{path});
}

pub fn handleList(io: std.Io, allocator: std.mem.Allocator, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !void {
    const path = "plants.json";
    std.Io.Dir.cwd().access(io, path, .{}) catch {
        try stderr.print("DB file might not be ready.", .{});
        return;
    };
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
    for (plantas) |plant| try printPlant(&plant, stdout, false);
}

fn printPlant(plant: *const Planta, stdout: *std.Io.Writer, showBitacora: bool) !void {
    try stdout.print("{s}\n", .{plant.nombreComun});
    try stdout.print("    ID:      {s}\n", .{plant.id});
    try stdout.print("    Tipo:    {s}\n", .{@tagName(plant.tipo)});
    try stdout.print("    Zona:    {s}\n", .{plant.zonaUbicacion});

    if (plant.especie) |esp| {
        try stdout.print("     Especie: {s}\n", .{esp});
    }

    if (plant.alturaActualCm) |h| {
        try stdout.print("    Altura:  {d} cm\n", .{h});
    }

    try stdout.print("    Nativo:  {s}\n", .{if (plant.nativo) "Sí" else "No"});

    if (plant.estado) |estado| {
        try stdout.print(".   Estado:  {s}\n", .{@tagName(estado)});
    }

    if (plant.notas) |n| {
        try stdout.print("    Notas: {s}\n", .{n});
    }

    try stdout.print("    Eventos en bitácora: {d}\n", .{plant.bitacora.len});
    try stdout.print("\n", .{});

    if (showBitacora and plant.bitacora.len > 0) {
        try stdout.print("    --- Bitácora ---\n", .{});
        for (plant.bitacora, 0..) |evento, i| {
            try stdout.print("    [{d}] {s} - {s}\n", .{ i, evento.fecha, @tagName(evento.tipo) });
            if (evento.cantidadLitros) |litros| {
                try stdout.print("         Cantidad: {d} L\n", .{litros});
            }
            if (evento.notas) |n| {
                try stdout.print("         Notas: {s}\n", .{n});
            }
        }
    }

    if (plant.urlsDocumentacion.len > 0) {
        try stdout.print("\n    --- URLs ---\n", .{});
        for (plant.urlsDocumentacion, 0..) |url, i| {
            try stdout.print("    [{d}] {s}\n", .{ i, url });
        }
    }
}

fn findPlantById(plants: []const Planta, plantId: []const u8) ?*const Planta {
    for (plants) |*plant| {
        if (std.mem.eql(u8, plant.id, plantId)) return plant;
    }
    return null;
}

pub fn handleShowPlantById(io: std.Io, iter: anytype, allocator: std.mem.Allocator, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !void {
    const plantIdStr = iter.next() orelse {
        try stderr.print("Error: el id de la planta|árbol a mostrar\n", .{});
        return;
    };

    const path = "plants.json";
    std.Io.Dir.cwd().access(io, path, .{}) catch {
        try stderr.print("DB file might not be ready.\n", .{});
        return;
    };
    const contenido = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
    defer allocator.free(contenido);

    const parsed = try std.json.parseFromSlice([]Planta, allocator, contenido, .{});
    defer parsed.deinit();
    const plantas = parsed.value;

    if (findPlantById(plantas, plantIdStr)) |plant| {
        try printPlant(plant, stdout, true);
    } else {
        try stderr.print("Planta no encontrada ... :(\n", .{});
    }
}

pub fn handleLog(
    io: std.Io,
    iter: anytype,
    allocator: std.mem.Allocator,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    // 1. Get the ID of the plant:
    const plant_id = iter.next() orelse {
        try stderr.print("Error: falta el ID de la planta\n", .{});
        return;
    };

    // Variables para el evento:
    var tipo_str: []const u8 = "";
    var cantidad: ?u32 = null;
    var notas: ?[]const u8 = null;

    // Parsear opciones:
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--tipo")) {
            tipo_str = iter.next() orelse {
                try stderr.print("Error: --tipo requiere un valor\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--cantidad")) {
            const cantidad_str = iter.next() orelse {
                try stderr.print("Error: --cantidad requiere un valor\n", .{});
                return;
            };
            cantidad = std.fmt.parseInt(u32, cantidad_str, 10) catch {
                try stderr.print("Error: --cantidad debe de ser un número\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--notas")) {
            notas = iter.next() orelse {
                try stderr.print("Error: --notas requiere un valor\n", .{});
                return;
            };
        } else {
            try stderr.print("Opción desconocida: {s}\n", .{arg});
        }
    }

    if (tipo_str.len == 0) {
        try stderr.print("Error: --tipo es obligatorio\n", .{});
        return;
    }

    // 4. Convertir tipo_str a TipoEvento
    const tipo = std.meta.stringToEnum(TipoEvento, tipo_str) orelse {
        try stderr.print("Error: tipo inválido '{s}'. Usa: riego, poda, fertilizante, plaga u otro\n", .{tipo_str});
        return;
    };

    // 5. Cargar plantas
    const path = "plants.json";
    std.Io.Dir.cwd().access(io, path, .{}) catch {
        try stderr.print("No hay plantas registradas.\n", .{});
        return;
    };

    const contenido = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
    defer allocator.free(contenido);

    const parsed = try std.json.parseFromSlice([]Planta, allocator, contenido, .{});
    defer parsed.deinit();

    var plantas: std.ArrayList(Planta) = .empty;
    defer plantas.deinit(allocator);

    try plantas.appendSlice(allocator, parsed.value);

    // 6. Buscar la planta
    const plantIndex = blk: {
        for (plantas.items, 0..) |plant, i| {
            if (std.mem.eql(u8, plant.id, plant_id)) {
                break :blk i;
            }
        }
        try stderr.print("Planta con ID '{s}' no encontrada.\n", .{plant_id});
        return;
    };

    // 7. Crear el nuevo evento:
    const now = std.Io.Clock.real.now(io);
    const timestamp_segundos = @divTrunc(now.nanoseconds, std.time.ns_per_s);
    const fecha = try std.fmt.allocPrint(allocator, "{d}", .{timestamp_segundos});
    defer allocator.free(fecha);

    const evento = EventoCuidado{
        .fecha = fecha,
        .tipo = tipo,
        .cantidadLitros = cantidad,
        .notas = notas,
    };

    // 8. Agregar el evento a la bitácora de la planta.
    var planta = plantas.items[plantIndex];
    var bitacora: std.ArrayList(EventoCuidado) = .empty;
    defer bitacora.deinit(allocator);

    try bitacora.appendSlice(allocator, planta.bitacora);
    try bitacora.append(allocator, evento);

    const nuevaBitacora = try bitacora.toOwnedSlice(allocator);
    defer allocator.free(nuevaBitacora);
    planta.bitacora = nuevaBitacora;
    plantas.items[plantIndex] = planta;

    // 9. Guardar todo
    try guardarPlantas(path, plantas, io);

    try stdout.print("Evento agregado correctamente a la planta {s}\n", .{plant_id});
}

pub fn handleEdit(
    io: std.Io,
    iter: anytype,
    allocator: std.mem.Allocator,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    // 1. Obtener el ID:
    const plantId = iter.next() orelse {
        try stderr.print("Error: falta el ID de la planta.\n", .{});
        return;
    };

    // 2. Variables para los campos que se pueden actualizar:
    var newZona: ?[]const u8 = null;
    var newAltura: ?u32 = null;
    var newNativo: ?bool = null;
    var newNotas: ?[]const u8 = null;
    var newEspecie: ?[]const u8 = null;
    var newNombre: ?[]const u8 = null;
    var newTipo: ?TipoPlanta = null;
    var newFechaPlantado: ?[]const u8 = null;
    var newUrls: std.ArrayList([]const u8) = .empty;
    defer newUrls.deinit(allocator);
    var urlsToAdd: std.ArrayList([]const u8) = .empty;
    var estadoSalud: ?EstadoSalud = null;
    defer urlsToAdd.deinit(allocator);

    var urlIndicesToRemove: std.ArrayList(usize) = .empty;
    defer urlIndicesToRemove.deinit(allocator);

    // 3. Parsear opciones
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--zona")) {
            newZona = iter.next() orelse {
                try stderr.print("Error: --zona requiere un valor\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--altura")) {
            const alturaStr = iter.next() orelse {
                try stderr.print("Error: --altura requiere un valor\n", .{});
                return;
            };
            newAltura = std.fmt.parseInt(u32, alturaStr, 10) catch {
                try stderr.print("Error: --altura debe ser un número\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--nativo")) {
            const nativoStr = iter.next() orelse {
                try stderr.print("Error: --nativo requiere un valor (true|false)\n", .{});
                return;
            };
            if (std.mem.eql(u8, nativoStr, "true")) {
                newNativo = true;
            } else if (std.mem.eql(u8, nativoStr, "false")) {
                newNativo = false;
            } else {
                try stderr.print("Error: --nativo debe ser 'true' o 'false'\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--notas")) {
            newNotas = iter.next() orelse {
                try stderr.print("Error: --notas requiere un valor.\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--especie")) {
            newEspecie = iter.next() orelse {
                try stderr.print("Error: --especie requiere un valor.\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--nombre")) {
            newNombre = iter.next() orelse {
                try stderr.print("Error: --nombre requiere un valor.\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--tipo")) {
            const tipoStr = iter.next() orelse {
                try stderr.print("Error: --tipo requiere un valor.\n", .{});
                return;
            };
            newTipo = std.meta.stringToEnum(TipoPlanta, tipoStr) orelse {
                try stderr.print("Tipo inválido: {s}, usa 'arbol', 'arbusto', 'cactacea'\n", .{tipoStr});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--estado")) {
            const estadoSaludStr = iter.next() orelse {
                try stderr.print("Error: --estado requiere un valor\n", .{});
                return;
            };
            estadoSalud = std.meta.stringToEnum(EstadoSalud, estadoSaludStr) orelse {
                try stderr.print("Error: estado inválido '{s}'. Usa: sana, enferma, recuperacion o muerta \n", .{estadoSaludStr});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--fecha-plantado")) {
            newFechaPlantado = iter.next() orelse {
                try stderr.print("Error: --fecha-plantado requiere un valor\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--url")) {
            const url = iter.next() orelse {
                try stderr.print("Error: --url requiere un valor.\n", .{});
                return;
            };
            try newUrls.append(allocator, url);
        } else if (std.mem.eql(u8, arg, "--url-add")) {
            const url = iter.next() orelse {
                try stderr.print("Error: --url-add requiere un valor.\n", .{});
                return;
            };
            try urlsToAdd.append(allocator, url);
        } else if (std.mem.eql(u8, arg, "--url-remove-index")) {
            const indexStr = iter.next() orelse {
                try stderr.print("Error: --url-remove-index requiere un valor.\n", .{});
                return;
            };

            const idx = std.fmt.parseInt(usize, indexStr, 10) catch {
                try stderr.print("Error: --url-remove-index debe ser un número\n", .{});
                return;
            };
            try urlIndicesToRemove.append(allocator, idx);
        } else {
            try stderr.print("Opción desconocida: {s}\n", .{arg});
        }
    }

    // 4. Cargar plantas
    const path = "plants.json";
    std.Io.Dir.cwd().access(io, path, .{}) catch {
        try stderr.print("No hay plantas registradas.\n", .{});
        return;
    };

    const contenido = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
    defer allocator.free(contenido);

    const parsed = try std.json.parseFromSlice([]Planta, allocator, contenido, .{});
    defer parsed.deinit();

    var plantas: std.ArrayList(Planta) = .empty;
    defer plantas.deinit(allocator);
    try plantas.appendSlice(allocator, parsed.value);

    // 5. Buscar la planta
    const plantIndex = blk: {
        for (plantas.items, 0..) |plant, i| {
            if (std.mem.eql(u8, plant.id, plantId)) break :blk i;
        }
        try stderr.print("Planta con ID '{s}' no encontrada.\n", .{plantId});
        return;
    };

    // 6. Actualizar solo los campos que se proporcionaron
    var planta = plantas.items[plantIndex];
    if (newNombre) |val| planta.nombreComun = val;
    if (newEspecie) |val| planta.especie = val;
    if (newZona) |val| planta.zonaUbicacion = val;
    if (newAltura) |val| planta.alturaActualCm = val;
    if (newNotas) |val| planta.notas = val;
    if (newNativo) |val| planta.nativo = val;
    if (newTipo) |val| planta.tipo = val;
    if (newFechaPlantado) |val| planta.fechaPlantado = val;
    if (estadoSalud) |val| planta.estado = val;
    if (newUrls.items.len > 0) {
        planta.urlsDocumentacion = try newUrls.toOwnedSlice(allocator);
    } else if (urlsToAdd.items.len > 0 or urlIndicesToRemove.items.len > 0) {
        // Construir lista nueva a partir de la existente.
        var lista: std.ArrayList([]const u8) = .empty;
        defer lista.deinit(allocator);

        for (planta.urlsDocumentacion, 0..) |url, i| {
            // Saltar los índices marcados para eliminar:
            var remover = false;
            for (urlIndicesToRemove.items) |idx| {
                if (idx == i) {
                    remover = true;
                    break;
                }
            }
            if (!remover) {
                try lista.append(allocator, url);
            }
        }

        // Agregar las nuevas:
        for (urlsToAdd.items) |url| {
            try lista.append(allocator, url);
        }

        planta.urlsDocumentacion = try lista.toOwnedSlice(allocator);
    }

    plantas.items[plantIndex] = planta;

    // Guardar cambios
    try guardarPlantas(path, plantas, io);

    try stdout.print("✅ Planta actualizada correctamente: {s}\n", .{plantId});
}

pub fn handleBackup(
    io: std.Io,
    allocator: std.mem.Allocator,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    const sourcePath = "plants.json";

    // Verificar que exista el archivo:
    std.Io.Dir.cwd().access(io, sourcePath, .{}) catch {
        try stderr.print("No existe el archivo plants.json para hacer el backup.\n", .{});
        return;
    };

    // Date / handling...
    const now = std.Io.Clock.real.now(io);
    const timestamp = @divTrunc(now.nanoseconds, std.time.ns_per_s);
    const ts_u64: u64 = @intCast(timestamp);
    const epochSeconds = std.time.epoch.EpochSeconds{ .secs = ts_u64 };
    const epochDay = epochSeconds.getEpochDay();
    const yearDay = epochDay.calculateYearDay();
    const monthDay = yearDay.calculateMonthDay();
    const daySeconds = epochSeconds.getDaySeconds();

    const year = yearDay.year;
    const month = monthDay.month.numeric();
    const day = monthDay.day_index + 1;
    const hour = daySeconds.getHoursIntoDay();
    const minute = daySeconds.getMinutesIntoHour();
    const second = daySeconds.getSecondsIntoMinute();

    const backupName = try std.fmt.allocPrint(
        allocator,
        "plants.json.{d}-{d:0>2}-{d:0>2}_{d:0>2}{d:0>2}{d:0>2}",
        .{ year, month, day, hour, minute, second },
    );

    defer allocator.free(backupName);

    // try std.fs.cwd().copyFile(sourcePath, backupName, .{});
    const contenido = try std.Io.Dir.cwd().readFileAlloc(io, sourcePath, allocator, .limited(10 * 1024 * 1024));
    defer allocator.free(contenido);

    const archivo = try std.Io.Dir.cwd().createFile(io, backupName, .{ .truncate = true });
    defer archivo.close(io);

    var buffer: [8192]u8 = undefined;
    var fw = archivo.writer(io, &buffer);
    try fw.interface.writeAll(contenido);
    try fw.interface.flush();

    try stdout.print("✅ Backup creado exitosamente: {s}\n", .{backupName});
}

pub fn handleHelp(stdout: *std.Io.Writer) !void {
    try stdout.print(
        \\mis-arbolitos-zig - Gestor de árboles y plantas para mi granjita familiar
        \\
        \\USO:
        \\    mis-arbolitos-zig <comando> [opciones]
        \\
        \\COMANDOS:
        \\    add      Agregar una nueva planta
        \\    list     Listar todas las plantas
        \\    show     Mostrar detalles de una planta (incluye bitácora)
        \\    edit     Modificar una planta existente
        \\    log      Agregar un evento a la bitácora de una planta
        \\    delete   Eliminar una planta
        \\    search   Buscar plantas por nombre
        \\    backup   Crear respaldo del archivo plants.json
        \\    info     Mostrar mapa de la granjita
        \\    help     Mostrar esta ayuda
        \\
        \\ADD  mis-arbolitos-zig add <tipo> <nombre> [opciones]
        \\    <tipo>                arbol | arbusto | cactacea
        \\    <nombre>              Nombre común de la planta (obligatorio)
        \\    --zona <zona>         Zona o ubicación dentro de la granjita
        \\    --especie <nombre>    Nombre científico
        \\    --altura <cm>         Altura actual en centímetros
        \\    --nativo true|false   Si es una especie nativa
        \\    --fecha-plantado <f>  Fecha en que se plantó (ej. 2024-03-15)
        \\    --estado <estado>     sana | enferma | recuperacion | muerta
        \\    --notas <texto>       Notas adicionales
        \\    --url <url>           URL de documentación (repetible)
        \\
        \\EDIT  mis-arbolitos-zig edit <id> [opciones]
        \\    <id>                        ID de la planta a modificar
        \\    --nombre <nombre>           Nuevo nombre común
        \\    --tipo <tipo>               arbol | arbusto | cactacea
        \\    --zona <zona>               Nueva zona o ubicación
        \\    --especie <nombre>          Nuevo nombre científico
        \\    --altura <cm>               Nueva altura en centímetros
        \\    --nativo true|false         Actualizar si es nativa
        \\    --fecha-plantado <f>        Nueva fecha de plantado
        \\    --estado <estado>           sana | enferma | recuperacion | muerta
        \\    --notas <texto>             Nuevas notas
        \\    --url <url>                 Reemplaza toda la lista de URLs (repetible)
        \\    --url-add <url>             Agrega una URL a la lista existente (repetible)
        \\    --url-remove-index <n>      Elimina la URL en el índice n (repetible)
        \\
        \\LOG  mis-arbolitos-zig log <id> --tipo <tipo> [opciones]
        \\    <id>               ID de la planta
        \\    --tipo <tipo>      riego | poda | fertilizante | plaga | otro (obligatorio)
        \\    --cantidad <l>     Cantidad de agua en litros (para riego)
        \\    --notas <texto>    Notas del evento
        \\
        \\SEARCH  mis-arbolitos-zig search <término>
        \\        mis-arbolitos-zig search --regex <patrón>
        \\    Busca en el nombre común. Sin --regex la búsqueda es insensible a mayúsculas.
        \\
        \\EJEMPLOS:
        \\    # Agregar un olivo con especie, zona y URL
        \\    mis-arbolitos-zig add arbol "Olivo" --zona "Patio principal" \
        \\        --especie "Olea europaea" --url "https://es.wikipedia.org/wiki/Olea_europaea"
        \\
        \\    # Agregar un nopal marcándolo como nativo
        \\    mis-arbolitos-zig add cactacea "Nopal" --zona "Cerca norte" --nativo true
        \\
        \\    # Listar todas las plantas
        \\    mis-arbolitos-zig list
        \\
        \\    # Ver detalles de una planta (incluye bitácora y URLs)
        \\    mis-arbolitos-zig show planta-1749500000
        \\
        \\    # Actualizar zona, altura y estado de salud
        \\    mis-arbolitos-zig edit planta-1749500000 --zona "Patio trasero" \
        \\        --altura 280 --estado recuperacion
        \\
        \\    # Agregar URL a una planta sin borrar las existentes
        \\    mis-arbolitos-zig edit planta-1749500000 --url-add "https://ejemplo.com"
        \\
        \\    # Agregar evento de riego
        \\    mis-arbolitos-zig log planta-1749500000 --tipo riego --cantidad 20 \
        \\        --notas "Agua de lluvia"
        \\
        \\    # Buscar por nombre (insensible a mayúsculas)
        \\    mis-arbolitos-zig search fresno
        \\
        \\    # Buscar con expresión regular
        \\    mis-arbolitos-zig search --regex "^[Nn]o"
        \\
        \\    # Eliminar una planta
        \\    mis-arbolitos-zig delete planta-1749500000
        \\
        \\    # Crear respaldo
        \\    mis-arbolitos-zig backup
        \\
        \\    # Ver mapa de la granjita
        \\    mis-arbolitos-zig info
        \\
    , .{});
}

pub fn handleDelete(io: std.Io, iter: anytype, allocator: std.mem.Allocator, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !void {
    const plantIdStr = iter.next() orelse {
        try stderr.print("Error: el id de la planta|árbol a eliminar faltante\n", .{});
        return;
    };

    const path = "plants.json";
    std.Io.Dir.cwd().access(io, path, .{}) catch {
        try stderr.print("DB file might not be ready.\n", .{});
        return;
    };
    const contenido = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
    defer allocator.free(contenido);

    const parsed = try std.json.parseFromSlice([]Planta, allocator, contenido, .{});
    defer parsed.deinit();
    const plantas = parsed.value;

    var deleteIdx: ?usize = null;
    for (plantas, 0..) |plantita, i| {
        if (std.mem.eql(u8, plantita.id, plantIdStr)) {
            deleteIdx = i;
            break;
        }
    }

    if (deleteIdx) |idx| {
        // Copy to an ArrayList (we can mutate it)
        var list: std.ArrayList(Planta) = .empty;
        defer list.deinit(allocator);

        try list.appendSlice(allocator, plantas);
        _ = list.orderedRemove(idx);

        try guardarPlantas(path, list, io);

        try stdout.print("Planta con id '{s}' eliminada correctamente.\n", .{plantIdStr});
    } else {
        try stderr.print("Error: no existe una planta con id '{s}'.\n", .{plantIdStr});
    }
}

const PlantsResult = struct {
    parsed: std.json.Parsed([]Planta),
    contenido: []u8,

    pub fn deinit(self: PlantsResult, allocator: std.mem.Allocator) void {
        self.parsed.deinit();
        allocator.free(self.contenido);
    }

    pub fn plants(self: PlantsResult) []Planta {
        return self.parsed.value;
    }
};

pub fn getPlantsFromFile(plantasFilePath: []const u8, allocator: std.mem.Allocator, io: std.Io, stderr: *std.Io.Writer) !PlantsResult {
    std.Io.Dir.cwd().access(io, plantasFilePath, .{}) catch |err| {
        try stderr.print("DB file might not be ready.\n", .{});
        return err;
    };

    const contenido = try std.Io.Dir.cwd().readFileAlloc(io, plantasFilePath, allocator, .limited(1024 * 1024));
    errdefer allocator.free(contenido);

    const parsed = try std.json.parseFromSlice([]Planta, allocator, contenido, .{});
    return .{ .parsed = parsed, .contenido = contenido };
}

pub fn handleSearch(io: std.Io, iter: *std.process.Args.Iterator, allocator: std.mem.Allocator, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !void {
    // 1. Obtener el tipo:
    const seachOrRegexOption = iter.next() orelse {
        try stdout.print("Error: search argument or --regex missing\n", .{});
        return;
    };

    if (std.mem.eql(u8, seachOrRegexOption, "--regex")) {
        const regexPattern = iter.next() orelse {
            try stdout.print("Error: falta el tipo (arbol|arbusto|cactacea)\n", .{});
            return;
        };
        // Use the regex
        // try stdout.print("Value to use for regex: [{s}]\n", .{regexPattern});
        var regex = try Regex.compile(allocator, regexPattern);
        defer regex.deinit();

        const result = try getPlantsFromFile("plants.json", allocator, io, stderr);
        defer result.deinit(allocator);
        const plantas = result.plants();

        for (plantas) |planta| {
            if (try regex.isMatch(planta.nombreComun)) {
                try printPlant(&planta, stdout, false);
            }
        }
        return;
    } else {
        const whatToSearch = seachOrRegexOption;

        const result = try getPlantsFromFile("plants.json", allocator, io, stderr);
        defer result.deinit(allocator);
        const plantas = result.plants();

        for (plantas) |planta| {
            var needleLower: [256]u8 = undefined;
            var haystackLower: [256]u8 = undefined;
            const needle = std.ascii.lowerString(&needleLower, whatToSearch);
            const haystack = std.ascii.lowerString(&haystackLower, planta.nombreComun);
            if (std.mem.indexOf(u8, haystack, needle) != null) {
                try printPlant(&planta, stdout, false);
            }
        }
    }
}

pub fn handleInfo(stdout: *std.Io.Writer) !void {
    try stdout.print(
        \\
        \\                                    (norte)
        \\         ╔═══════════════════════════════════════════════════════════╗
        \\         ║                  ║   ║    ║   ║                 ║         ║
        \\         ║                  ║   ║    ║   ║                 ║         ║
        \\         ║                  ╚════════════╝         C       ╚═════════║
        \\         ║                                       C     C             ║
        \\         ║                                     C         C           ║
        \\         ║                                    C            C         ║
        \\         ║                                      C            C       ║
        \\         ║                                        C        C         ║
        \\         ║                                          C   C            ║
        \\         ║══════════════╗                            C               ║
        \\         ║              ║                                AAAAAA      ║
        \\         ║              ║                                A    A      ║
        \\ I (Oeste)              ║                                A    A      ║ D (Este)
        \\         ║              ║                                A    A      ║
        \\         ║              ║                                AAAAAA      ║
        \\         ║══════════════╝                                            ║
        \\         ║                                                           ║
        \\         ║                                                           ║
        \\         ║                                                           ║
        \\         ║                                                           ║
        \\         ║   N                                                 N     ║
        \\         ║   N                               ╔═╗               N     ║
        \\         ║   N                               ╚═╝               N     ║
        \\         ║                                                           ║
        \\         ╚═══════════════════════════Portón══════════════════════════╝
        \\                                     (sur)
        \\
    , .{});
}
