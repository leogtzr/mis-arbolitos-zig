const std = @import("std");

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

    var urls: std.ArrayList([]const u8) = .empty;
    defer urls.deinit(allocator);

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
    };

    try guardarPlanta(planta, io, allocator, stdout);
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
    const archivo = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer archivo.close(io);

    var buffer: [4096]u8 = undefined;
    var fw = archivo.writer(io, &buffer);
    try std.json.Stringify.value(plantas.items, .{ .whitespace = .indent_4 }, &fw.interface);
    try fw.interface.flush();

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
    // const fecha = try std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}", .{
    //     @divTrunc(now.nanoseconds, std.time.ns_per_day * 365) + 1970, // Año aproximado
    //     @mod(@divTrunc(@mod(now.nanoseconds, std.time.ns_per_day), std.time.ns_per_hour), 12) + 1, // Mes simplificado
    //     @mod(@divTrunc(@mod(now.nanoseconds, std.time.ns_per_day), std.time.ns_per_hour), 31) + 1, // Día simplificado
    // });
    //
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
    const archivo = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer archivo.close(io);

    var buffer: [8192]u8 = undefined;
    var fw = archivo.writer(io, &buffer);
    try std.json.Stringify.value(plantas.items, .{ .whitespace = .indent_4 }, &fw.interface);
    try fw.interface.flush();

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
    const archivo = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer archivo.close(io);

    var buffer: [8192]u8 = undefined;
    var fw = archivo.writer(io, &buffer);
    try std.json.Stringify.value(plantas.items, .{ .whitespace = .indent_4 }, &fw.interface);
    try fw.interface.flush();

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
        \\mis-arbolitos-zig - Gestor de árboles y arbustos para mi granjita familiar
        \\
        \\USO:
        \\    mis-arbolitos-zig <comando> [opciones]
        \\
        \\COMANDOS:
        \\    add     Agregar una nueva planta
        \\    list    Listar todas las plantas
        \\    show    Mostrar detalles de una planta (incluye bitácora)
        \\    edit    Modificar una planta existente
        \\    log     Agregar un evento a la bitácora de una planta
        \\    help    Mostrar esta ayuda
        \\
        \\EJEMPLOS:
        \\    # Agregar una planta con URLs
        \\    mis-arbolitos-zig add arbol "Olivo" --zona "Patio principal" \
        \\        --url "https://es.wikipedia.org/wiki/Olea_europaea"
        \\
        \\    # Listar todas las plantas
        \\    mis-arbolitos-zig list
        \\
        \\    # Ver detalles de una planta (incluye bitácora)
        \\    mis-arbolitos-zig show planta-1749500000
        \\
        \\    # Actualizar zona y altura
        \\    mis-arbolitos-zig edit planta-1749500000 --zona "Patio trasero" --altura 280
        \\
        \\    # Agregar evento de riego
        \\    mis-arbolitos-zig log planta-1749500000 --tipo riego --cantidad 20 --notas "Agua normal"
        \\
        \\    # Ver ayuda
        \\    mis-arbolitos-zig help
        \\
    , .{});
}
