const std = @import("std");

pub fn Ratio(comptime T: type) type {
    return struct {
        antecedent: T,
        consequent: T,

        const Self = @This();

        pub fn toF64(self: Self) f64 {
            return @as(f64, @floatFromInt(self.antecedent)) /
                @as(f64, @floatFromInt(self.consequent));
        }

        fn gcd(a: T, b: T) T {
            var x = a;
            var y = b;
            while (y != 0) {
                const tmp = y;
                y = x % tmp;
                x = tmp;
            }
            return x;
        }

        pub fn flip(self: *Self) void {
            const a = self.antecedent;
            const c = self.consequent;

            self.antecedent = c;
            self.consequent = a;
        }

        pub fn reduced(self: Self) Self {
            const d = gcd(self.antecedent, self.consequent);
            return .{ .antecedent = self.antecedent / d, .consequent = self.consequent / d };
        }
    };
}

pub const OrbitalParams = struct {
    body: CelestialBody,
    inclination: f64,
    semi_major_axis: f64,
    eccentricity: f64,
    lan: ?f64 = null,
    arg_of_periapsis: ?f64 = null,
    true_anomaly: ?f64 = null,
    frame: ?ReferenceFrame = null,

    pub fn initSimple(body: CelestialBody, apo: f64, peri: f64, incl: f64) OrbitalParams {
        const radius = body.radius();
        const apo_r = radius + apo;
        const peri_r = radius + peri;
        const sma = (apo_r + peri_r) / 2.0;
        const ecc = 1.0 - peri_r / sma;
        return .{
            .body = body,
            .inclination = incl,
            .semi_major_axis = sma,
            .eccentricity = ecc,
        };
    }

    /// Returns the resonant orbit for a given ratio.
    /// `dive` = true: Ap is held fixed, Pe shortens (inside pass, faster).
    /// `dive` = false: Pe is held fixed, Ap raises (outside pass, slower).
    pub fn resonant(self: OrbitalParams, ratio: Ratio(u32), dive: bool) OrbitalParams {
        var rat = ratio;
        rat.antecedent = @max(1, rat.antecedent);
        rat.consequent = @max(1, rat.consequent);
        if (dive) rat.flip();

        const rat_f = rat.toF64();
        const res_sma = self.semi_major_axis * std.math.pow(f64, rat_f, 2.0 / 3.0);
        const res_ecc = if (dive) blk: {
            const apo_r = self.apoapsis() + self.body.radius();
            break :blk apo_r / res_sma - 1.0;
        } else blk: {
            const peri_r = self.periapsis() + self.body.radius();
            break :blk 1.0 - peri_r / res_sma;
        };

        return .{
            .body = self.body,
            .inclination = self.inclination,
            .semi_major_axis = res_sma,
            .eccentricity = res_ecc,
            .lan = self.lan,
            .arg_of_periapsis = self.arg_of_periapsis,
            .frame = self.frame,
        };
    }

    pub fn transferDv(circular: OrbitalParams, res: OrbitalParams, dive: bool) f64 {
        const mu = circular.body.mu();
        // The burn happens at the shared point
        const r = if (dive)
            circular.apoapsis() + circular.body.radius() // Ap is shared for dive
        else
            circular.periapsis() + circular.body.radius(); // Pe is shared for raise

        const v_circ = std.math.sqrt(mu * (2.0 / r - 1.0 / circular.semi_major_axis));
        const v_res = std.math.sqrt(mu * (2.0 / r - 1.0 / res.semi_major_axis));

        return @abs(v_res - v_circ);
    }

    pub fn apoapsis(self: OrbitalParams) f64 {
        return self.semi_major_axis * (1.0 + self.eccentricity) - self.body.radius();
    }

    pub fn periapsis(self: OrbitalParams) f64 {
        return self.semi_major_axis * (1.0 - self.eccentricity) - self.body.radius();
    }

    pub fn apoF32(self: OrbitalParams) f32 {
        return @floatCast(self.apoapsis());
    }

    pub fn periF32(self: OrbitalParams) f32 {
        return @floatCast(self.periapsis());
    }

    /// Returns orbital period in seconds.
    pub fn period(self: OrbitalParams) f64 {
        return 2.0 * std.math.pi * std.math.sqrt(
            std.math.pow(f64, self.semi_major_axis, 3.0) / self.body.mu(),
        );
    }

    pub fn periodF32(self: OrbitalParams) f32 {
        return @floatCast(self.period());
    }
};

test "OrbitalParams" {
    const kerbin: CelestialBody = .kerbin;
    const pe_alt = 80_000.0;
    const ap_alt = 2_200_000.0;
    const r_pe = kerbin.radius() + pe_alt;
    const r_ap = kerbin.radius() + ap_alt;
    const sma = (r_pe + r_ap) / 2.0;
    const ecc = (r_ap - r_pe) / (r_ap + r_pe);

    const orbit = OrbitalParams{
        .body = kerbin,
        .semi_major_axis = sma,
        .eccentricity = ecc,
        .inclination = std.math.degreesToRadians(64.0),
        .lan = 0.0,
        .arg_of_periapsis = 0.0,
        .true_anomaly = 0.0,
        .frame = .{ .inertial = .equatorial_j2000 },
    };

    try std.testing.expectApproxEqAbs(pe_alt, orbit.periapsis(), 1.0);
    try std.testing.expectApproxEqAbs(ap_alt, orbit.apoapsis(), 1.0);

    // SMA roundtrip via altitudes
    const sma_roundtrip = (orbit.apoapsis() + orbit.periapsis()) / 2.0 + kerbin.radius();
    try std.testing.expectApproxEqAbs(sma, sma_roundtrip, 1.0);

    // Period ~2h 32m for this orbit
    try std.testing.expectApproxEqAbs(7_674.0, orbit.period(), 50.0);

    // f32 casts
    try std.testing.expectApproxEqAbs(@as(f32, @floatCast(ap_alt)), orbit.apoF32(), 1000.0);
    try std.testing.expectApproxEqAbs(@as(f32, @floatCast(pe_alt)), orbit.periF32(), 1000.0);
    try std.testing.expectApproxEqAbs(@as(f32, @floatCast(orbit.period())), orbit.periodF32(), 1.0);
}

pub const ReferenceFrame = union(enum) {
    inertial: InertialFrame,
    body_fixed: CelestialBody,
    // synodic: SynodicFrame,
    perifocal,
};

pub const InertialFrame = enum {
    ecliptic_j2000,
    equatorial_j2000,
    custom,
};

pub const BodyTag = enum {
    kerbol,
    moho,
    eve,
    gilly,
    kerbin,
    mun,
    minmus,
    duna,
    ike,
    dres,
    jool,
    laythe,
    vall,
    tylo,
    bop,
    pol,
    eeloo,
    sol,
    mercury,
    venus,
    earth,
    luna,
    mars,
    phobos,
    deimos,
    jupiter,
    io,
    europa,
    ganymede,
    callisto,
    saturn,
    titan,
    enceladus,
    mimas,
    tethys,
    dione,
    rhea,
    uranus,
    miranda,
    ariel,
    umbriel,
    titania,
    oberon,
    neptune,
    triton,
    pluto,
    custom,

    pub fn body(self: BodyTag) CelestialBody {
        return switch (self) {
            .custom => @panic("Cannot resolve custom BodyTag without params."),
            inline else => |t| @field(CelestialBody, @tagName(t)),
        };
    }
};

pub const CelestialBody = union(enum) {
    // KSP
    kerbol,
    moho,
    eve,
    gilly,
    kerbin,
    mun,
    minmus,
    duna,
    ike,
    dres,
    jool,
    laythe,
    vall,
    tylo,
    bop,
    pol,
    eeloo,
    // Real
    sol,
    mercury,
    venus,
    earth,
    luna,
    mars,
    phobos,
    deimos,
    jupiter,
    io,
    europa,
    ganymede,
    callisto,
    saturn,
    titan,
    enceladus,
    mimas,
    tethys,
    dione,
    rhea,
    uranus,
    miranda,
    ariel,
    umbriel,
    titania,
    oberon,
    neptune,
    triton,
    pluto,

    custom: BodyParams,

    const Self = @This();

    pub fn params(self: Self) BodyParams {
        return switch (self) {
            .custom => |p| p,
            // KSP
            .kerbol => .{ .mu = 1.1723328e18, .radius = 261_600_000 },
            .moho => .{ .mu = 1.6860938e11, .radius = 250_000, .parent_body = .kerbol, .orbital_sma = 5_263_138_304 },
            .eve => .{ .mu = 8.1717302e12, .radius = 700_000, .parent_body = .kerbol, .orbital_sma = 9_832_684_544, .atmosphere_height = 90_000 },
            .gilly => .{ .mu = 8.2894498e6, .radius = 13_000, .parent_body = .eve, .orbital_sma = 31_500_000 },
            .kerbin => .{ .mu = 3.5316e12, .radius = 600_000, .parent_body = .kerbol, .orbital_sma = 13_599_840_256, .atmosphere_height = 70_000, .rotation_period = 21_549.425 },
            .mun => .{ .mu = 6.5138e10, .radius = 200_000, .parent_body = .kerbin, .orbital_sma = 12_000_000 },
            .minmus => .{ .mu = 1.7658e9, .radius = 60_000, .parent_body = .kerbin, .orbital_sma = 47_000_000 },
            .duna => .{ .mu = 3.0136321e11, .radius = 320_000, .parent_body = .kerbol, .orbital_sma = 20_726_155_264, .atmosphere_height = 50_000 },
            .ike => .{ .mu = 1.8568369e10, .radius = 130_000, .parent_body = .duna, .orbital_sma = 3_200_000 },
            .dres => .{ .mu = 2.1484489e10, .radius = 138_000, .parent_body = .kerbol, .orbital_sma = 40_839_348_203 },
            .jool => .{ .mu = 2.8252800e14, .radius = 6_000_000, .parent_body = .kerbol, .orbital_sma = 68_773_560_320, .atmosphere_height = 200_000 },
            .laythe => .{ .mu = 1.9620000e12, .radius = 500_000, .parent_body = .jool, .orbital_sma = 27_184_000, .atmosphere_height = 50_000 },
            .vall => .{ .mu = 2.0748150e11, .radius = 300_000, .parent_body = .jool, .orbital_sma = 43_152_000 },
            .tylo => .{ .mu = 2.8252800e12, .radius = 600_000, .parent_body = .jool, .orbital_sma = 68_500_000 },
            .bop => .{ .mu = 2.4868349e9, .radius = 65_000, .parent_body = .jool, .orbital_sma = 128_500_000 },
            .pol => .{ .mu = 7.2170208e8, .radius = 44_000, .parent_body = .jool, .orbital_sma = 179_890_000 },
            .eeloo => .{ .mu = 7.4410815e10, .radius = 210_000, .parent_body = .kerbol, .orbital_sma = 90_118_820_000 },
            // Real
            .sol => .{ .mu = 1.32712440018e20, .radius = 695_700_000 },
            .mercury => .{ .mu = 2.2032e13, .radius = 2_439_700, .parent_body = .sol, .orbital_sma = 57_909_050_000 },
            .venus => .{ .mu = 3.24859e14, .radius = 6_051_800, .parent_body = .sol, .orbital_sma = 108_208_000_000, .atmosphere_height = 250_000 },
            .earth => .{ .mu = 3.986004418e14, .radius = 6_371_000, .parent_body = .sol, .orbital_sma = 149_598_023_000, .atmosphere_height = 100_000, .rotation_period = 86_164.1 },
            .luna => .{ .mu = 4.9048695e12, .radius = 1_737_400, .parent_body = .earth, .orbital_sma = 384_400_000 },
            .mars => .{ .mu = 4.282837e13, .radius = 3_389_500, .parent_body = .sol, .orbital_sma = 227_939_200_000, .atmosphere_height = 125_000 },
            .phobos => .{ .mu = 7.087546e5, .radius = 11_267, .parent_body = .mars, .orbital_sma = 9_376_000 },
            .deimos => .{ .mu = 9.615569e4, .radius = 6_200, .parent_body = .mars, .orbital_sma = 23_463_200 },
            .jupiter => .{ .mu = 1.26686534e17, .radius = 69_911_000, .parent_body = .sol, .orbital_sma = 778_500_000_000, .atmosphere_height = 1_000_000 },
            .io => .{ .mu = 5.959916e12, .radius = 1_821_600, .parent_body = .jupiter, .orbital_sma = 421_800_000 },
            .europa => .{ .mu = 3.202739e12, .radius = 1_560_800, .parent_body = .jupiter, .orbital_sma = 671_100_000 },
            .ganymede => .{ .mu = 9.887834e12, .radius = 2_634_100, .parent_body = .jupiter, .orbital_sma = 1_070_400_000 },
            .callisto => .{ .mu = 7.179289e12, .radius = 2_410_300, .parent_body = .jupiter, .orbital_sma = 1_882_700_000 },
            .saturn => .{ .mu = 3.7931187e16, .radius = 58_232_000, .parent_body = .sol, .orbital_sma = 1_432_000_000_000, .atmosphere_height = 1_000_000 },
            .titan => .{ .mu = 8.978138e12, .radius = 2_574_700, .parent_body = .saturn, .orbital_sma = 1_221_870_000, .atmosphere_height = 600_000 },
            .enceladus => .{ .mu = 7.211454e9, .radius = 252_100, .parent_body = .saturn, .orbital_sma = 238_020_000 },
            .mimas => .{ .mu = 2.503524e9, .radius = 198_200, .parent_body = .saturn, .orbital_sma = 185_520_000 },
            .tethys => .{ .mu = 4.121918e10, .radius = 531_100, .parent_body = .saturn, .orbital_sma = 294_660_000 },
            .dione => .{ .mu = 7.311608e10, .radius = 561_400, .parent_body = .saturn, .orbital_sma = 377_400_000 },
            .rhea => .{ .mu = 1.539422e11, .radius = 763_800, .parent_body = .saturn, .orbital_sma = 527_040_000 },
            .uranus => .{ .mu = 5.7939399e15, .radius = 25_362_000, .parent_body = .sol, .orbital_sma = 2_867_000_000_000, .atmosphere_height = 1_000_000 },
            .miranda => .{ .mu = 4.319516e9, .radius = 235_800, .parent_body = .uranus, .orbital_sma = 129_900_000 },
            .ariel => .{ .mu = 8.346344e10, .radius = 578_900, .parent_body = .uranus, .orbital_sma = 191_020_000 },
            .umbriel => .{ .mu = 8.509338e10, .radius = 584_700, .parent_body = .uranus, .orbital_sma = 266_000_000 },
            .titania => .{ .mu = 2.269437e11, .radius = 788_400, .parent_body = .uranus, .orbital_sma = 435_910_000 },
            .oberon => .{ .mu = 1.976259e11, .radius = 761_400, .parent_body = .uranus, .orbital_sma = 583_520_000 },
            .neptune => .{ .mu = 6.8365299e15, .radius = 24_622_000, .parent_body = .sol, .orbital_sma = 4_515_000_000_000, .atmosphere_height = 1_000_000 },
            .triton => .{ .mu = 1.427598e12, .radius = 1_353_400, .parent_body = .neptune, .orbital_sma = 354_759_000 },
            .pluto => .{ .mu = 8.71e11, .radius = 1_188_300, .parent_body = .sol, .orbital_sma = 5_906_380_000_000 },
        };
    }

    pub fn mu(self: Self) f64 {
        return self.params().mu;
    }

    pub fn radius(self: Self) f64 {
        return self.params().radius;
    }

    pub fn soi(self: Self) ?f64 {
        if (self.params().parent_body) |pb| {
            if (self.params().orbital_sma) |sma| {
                return sma * std.math.pow(f64, self.mu() / pb.body().mu(), 0.4);
            }
        }
        return null;
    }

    pub fn scaled(self: Self, r: f64) f64 {
        return r / self.radius();
    }
};

pub const BodyParams = struct {
    mu: f64, // m³/s²  — gravitational parameter
    radius: f64, // m      — mean equatorial radius
    j2: ?f64 = null, // oblateness coefficient
    atmosphere_height: ?f64 = null, // m — null if no atmosphere
    rotation_period: ?f64 = null, // s — for surface velocity, GEO calc
    parent_body: ?BodyTag = null, // the body its orbiting
    orbital_sma: ?f64 = null, // m - sma for the body its orbiting
};

pub const FromJsonOpts = union(enum) {
    str: []const u8,
    path: PathOpts,

    pub const PathOpts = struct {
        io: std.Io,
        name: []const u8,
    };
};

pub fn fromJson(T: type, gpa: std.mem.Allocator, opts: FromJsonOpts) !std.json.Parsed(T) {
    const json = std.json;
    return switch (opts) {
        .str => |s| json.parseFromSlice(
            T,
            gpa,
            s,
            .{ .ignore_unknown_fields = true, .parse_numbers = true },
        ),
        .path => |p| blk: {
            const cwd: std.Io.Dir = std.Io.Dir.cwd();
            const contents = try cwd.readFileAlloc(p.io, p.name, gpa, .unlimited);
            defer gpa.free(contents);
            break :blk try json.parseFromSlice(
                T,
                gpa,
                contents,
                .{ .ignore_unknown_fields = true, .parse_numbers = true },
            );
        },
    };
}

test "BodyParams.fromJson" {
    const bp: std.json.Parsed(BodyParams) = try fromJson(
        BodyParams,
        std.testing.allocator,
        .{ .path = .{ .io = std.testing.io, .name = "test/body.json" } },
    );
    defer bp.deinit();

    try std.testing.expectEqual(bp.value.atmosphere_height, 70000.0);

    const json_str =
        \\{
        \\  "mu": 6.5138e10,
        \\  "radius": 200000.0,
        \\  "soi": 2429559.0
        \\}
    ;

    const bp2: std.json.Parsed(BodyParams) = try fromJson(
        BodyParams,
        std.testing.allocator,
        .{ .str = json_str },
    );
    defer bp2.deinit();

    try std.testing.expectEqual(bp2.value.mu, 6.5138e10);
}
