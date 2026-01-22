pub const BuildContext = struct {
    has_build_zig: bool,
    has_main_c: bool,
    has_main_cpp: bool,
    has_main_cc: bool,
    has_main_cxx: bool,
    has_cargo_toml: bool,
    has_go_mod: bool,
    has_requirements: bool,
    has_pyproject: bool,
    has_setup_py: bool,
};

pub const BuildPlan = union(enum) {
    ZigBuild,
    CompileC: []const u8,
    CompileCpp: []const u8,
    RustCargo,
    GoBuild,
    PythonInstallRequirements,
    PythonInstallProject,
    MissingSource,
    MissingCargoManifest,
    MissingGoModule,
    MissingPythonManifest,
    Unknown,
};
