// Janet build file (run `zig build --help` for more detailed overview):
//  * zig build       bootstrap a Janet interpreter and amalgamate
//  * zig build run   build Janet interpreter and run it
//  * zig build test  run Janet test suite (unit and behavior tests)

const std = @import("std");
const WriteFileStep = std.build.WriteFileStep;
const LibExeObjStep = std.build.LibExeObjStep;
const CSourceFile = std.build.CSourceFile;
const Builder = std.build.Builder;
const Step = std.build.Step;

pub fn build(b: *Builder) !void {
    // Standard release mode and cross target options.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    // Config struct to pass to other methods.
    const config = JanetConfig.options(b, mode);

    // Build the amalgamate source file.
    const generated_src = amalgamate(b, config);

    // Build a Janet standalone interpreter.
    const exe = b.addExecutable("janet", null);
    exe.step.dependOn(&generated_src.source.write_file.step.step);
    config.apply(exe);
    exe.addCSourceFileSource(generated_src);
    exe.addCSourceFile(
        std.fs.path.join(
            b.allocator,
            &[_][]const u8{ config.root_dir, "src", "mainclient", "shell.c" },
        ) catch unreachable,
        &[_][]const u8{},
    );
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.linkLibC();
    exe.install();

    // Build and run Janet standalone interpreter.
    const run_step = exe.run();
    if (b.args) |args|
        run_step.addArgs(args);
    run_step.step.dependOn(b.getInstallStep());
    b.step("run", "Build and run the application").dependOn(&run_step.step);
}

/// Janet configuration (corresponds to options available in janet_conf.h).
pub const JanetConfig = struct {
    /// The path in which the Janet repository is checked out.
    root_dir: []const u8,

    /// The path of the directory containing janet.h.
    include_dir: []const u8,

    /// The path of the directory containing janetconf.h.
    conf_dir: []const u8,

    // ===[Linking-related options]===
    single_threaded: bool = false,
    dynamic_modules: bool = true,
    nanbox: bool = true,

    // ===[Non-standard options]===
    reduced_os: bool = false,
    docstrings: bool = true,
    sourcemaps: bool = true,
    assembler: bool = true,
    typed_array: bool = true,
    int_types: bool = true,
    process_api: bool = true,
    peg_api: bool = true,
    net_api: bool = true,
    event_loop: bool = true,
    realpath: bool = true,
    symlinks: bool = true,
    umask: bool = true,

    // ===[Miscellaneous options]===
    debug: bool = false,
    prf: bool = false,
    utc_mktime: bool = true,
    ev_epoll: bool = false,
    recursion_guard: ?u32 = null,
    max_proto_depth: ?u32 = null,
    max_macro_expand: ?u32 = null,
    top_level_signal_macro: ?[]const u8 = null,
    out_of_memory_macro: ?[]const u8 = null,
    exit_macro: ?[]const u8 = null,
    stack_max: ?u32 = null,
    os_name: ?[]const u8 = null,
    arch_name: ?[]const u8 = null,

    // ===[Main client options]===
    simple_getline: bool = false,

    pub fn options(b: *Builder, mode: std.builtin.Mode) JanetConfig {
        return .{
            .root_dir = b.pathFromRoot("deps/janet"),
            .include_dir = b.pathFromRoot("deps/janet/src/include"),
            .conf_dir = b.pathFromRoot("deps/janet/src/conf"),
            .single_threaded = b.option(bool, "single-threaded", "Create a single threaded build") orelse false,
            .dynamic_modules = b.option(bool, "dynamic-modules", "Build with dynamic module support") orelse false,
            .reduced_os = b.option(bool, "reduced-os", "Reduce reliance on OS-specific APIs") orelse false,
            .nanbox = !(b.option(bool, "no-nanbox", "Disable nanboxing for Janet values") orelse false),
            .docstrings = !(b.option(bool, "no-docstrings", "Do not include docstrings in the core image") orelse false),
            .sourcemaps = !(b.option(bool, "no-sourcemaps", "Do not include sourcemaps in the core image") orelse false),
            .assembler = !(b.option(bool, "no-assembler", "Do not include the Janet bytecode assembly API") orelse false),
            .typed_array = !(b.option(bool, "no-typed-array", "Do not include the Janet typed array API") orelse false),
            .int_types = !(b.option(bool, "no-int-types", "Do not include the Janet integer types") orelse false),
            .process_api = !(b.option(bool, "no-process-api", "Do not include the Janet process API") orelse false),
            .peg_api = !(b.option(bool, "no-peg-api", "Do not include the Janet PEG API") orelse false),
            .net_api = !(b.option(bool, "no-net-api", "Do not include the Janet network API") orelse false),
            .event_loop = !(b.option(bool, "no-event-loop", "Do not include the Janet event loop") orelse false),
            .realpath = !(b.option(bool, "no-realpath", "Do not support realpath system call") orelse false),
            .symlinks = !(b.option(bool, "no-symlinks", "Do not support symlinks") orelse false),
            .umask = !(b.option(bool, "no-umask", "Do not support setting umask") orelse false),
            .utc_mktime = !(b.option(bool, "no-utc-mktime", "Do not use UTC with mktime") orelse false),
            .prf = b.option(bool, "prf-hash", "Enable PRF hash function") orelse false,
            .ev_epoll = b.option(bool, "use-epoll", "Use epoll in the event loop") orelse false,
            .simple_getline = b.option(bool, "simple-getline", "Use simple getline API in the main client") orelse false,
            .recursion_guard = b.option(u32, "recursion-guard", "Max recursion (default: 1024)"),
            .max_proto_depth = b.option(u32, "max-proto-depth", "Max prototype depth (default: 200)"),
            .max_macro_expand = b.option(u32, "max-macro-expand", "Maximum macro expansion (default: 200)"),
            .stack_max = b.option(u32, "stack-max", "Maximum number of Janet values in stack (default: 16384)"),
            .os_name = b.option([]const u8, "os_name", "Override OS name (default: based on target)"),
            .arch_name = b.option([]const u8, "arch_name", "Override arch name (default: based on target)"),
            .top_level_signal_macro = b.option([]const u8, "top-level-signal-macro", "Macro used to process top level signals"),
            .out_of_memory_macro = b.option([]const u8, "out-of-memory-macro", "Macro used on out-of-memory condition"),
            .exit_macro = b.option([]const u8, "assert-fail-macro", "Macro used to exit on assertion failure"),
            .debug = if (mode == .Debug) true else false,
        };
    }

    pub fn apply(config: JanetConfig, artifact: *LibExeObjStep) void {
        const b = artifact.builder;
        var buf = std.ArrayList(u8).init(b.allocator);
        defer buf.deinit();
        artifact.addIncludeDir(config.include_dir);
        artifact.addIncludeDir(config.conf_dir);
        if (config.single_threaded)
            artifact.defineCMacro("JANET_SINGLE_THREADED=1");
        if (!config.dynamic_modules)
            artifact.defineCMacro("JANET_NO_DYNAMIC_MODULES=1");
        if (!config.nanbox)
            artifact.defineCMacro("JANET_NO_NANBOX=1");
        if (config.reduced_os)
            artifact.defineCMacro("JANET_REDUCED_OS=1");
        if (!config.sourcemaps)
            artifact.defineCMacro("JANET_NO_SOURCEMAPS=1");
        if (!config.assembler)
            artifact.defineCMacro("JANET_NO_ASSEMBLER=1");
        if (!config.typed_array)
            artifact.defineCMacro("JANET_NO_ASSEMBLER=1");
        if (!config.int_types)
            artifact.defineCMacro("JANET_NO_INT_TYPES=1");
        if (!config.process_api)
            artifact.defineCMacro("JANET_NO_PROCESSES=1");
        if (!config.peg_api)
            artifact.defineCMacro("JANET_NO_PEG=1");
        if (!config.net_api)
            artifact.defineCMacro("JANET_NO_NET=1");
        if (!config.event_loop)
            artifact.defineCMacro("JANET_NO_EV=1");
        if (!config.realpath)
            artifact.defineCMacro("JANET_NO_REALPATH=1");
        if (!config.symlinks)
            artifact.defineCMacro("JANET_NO_SYMLINKS=1");
        if (!config.umask)
            artifact.defineCMacro("JANET_NO_UMASK=1");
        if (config.debug)
            artifact.defineCMacro("JANET_DEBUG=1");
        if (config.prf)
            artifact.defineCMacro("JANET_PRF=1");
        if (!config.utc_mktime)
            artifact.defineCMacro("JANET_NO_UTC_MKTIME=1");
        if (config.ev_epoll)
            artifact.defineCMacro("JANET_EV_EPOLL=1");
        if (config.simple_getline)
            artifact.defineCMacro("JANET_SIMPLE_GETLINE=1");
        if (config.recursion_guard) |i| {
            buf.writer().print("JANET_RECURSION_GUARD={}", .{i}) catch unreachable;
            artifact.defineCMacro(buf.items);
            buf.shrinkRetainingCapacity(0);
        }
        if (config.max_proto_depth) |i| {
            buf.writer().print("JANET_MAX_PROTO_DEPTH={}", .{i}) catch unreachable;
            artifact.defineCMacro(buf.items);
            buf.shrinkRetainingCapacity(0);
        }
        if (config.max_macro_expand) |i| {
            buf.writer().print("JANET_MAX_MACRO_EXPAND={}", .{i}) catch unreachable;
            artifact.defineCMacro(buf.items);
            buf.shrinkRetainingCapacity(0);
        }
        if (config.top_level_signal_macro) |i| {
            buf.writer().print("JANET_TOP_LEVEL_SIGNAL(msg)={s}", .{i}) catch unreachable;
            artifact.defineCMacro(buf.items);
            buf.shrinkRetainingCapacity(0);
        }
        if (config.out_of_memory_macro) |i| {
            buf.writer().print("JANET_OUT_OF_MEMORY={s}", .{i}) catch unreachable;
            artifact.defineCMacro(buf.items);
            buf.shrinkRetainingCapacity(0);
        }
        if (config.exit_macro) |i| {
            buf.writer().print("JANET_EXIT(msg)={s}", .{i}) catch unreachable;
            artifact.defineCMacro(buf.items);
            buf.shrinkRetainingCapacity(0);
        }
        if (config.stack_max) |i| {
            buf.writer().print("JANET_STACK_MAX={}", .{i}) catch unreachable;
            artifact.defineCMacro(buf.items);
            buf.shrinkRetainingCapacity(0);
        }
        if (config.os_name) |i| {
            buf.writer().print("JANET_OS_NAME={s}", .{i}) catch unreachable;
            artifact.defineCMacro(buf.items);
            buf.shrinkRetainingCapacity(0);
        }
        if (config.arch_name) |i| {
            buf.writer().print("JANET_ARCH_NAME={s}", .{i}) catch unreachable;
            artifact.defineCMacro(buf.items);
            buf.shrinkRetainingCapacity(0);
        }
    }
};

/// Return a `CSourceFile` that can be passed to `LibExeObjStep.addCSourceFileSource`.
pub fn amalgamate(b: *Builder, config: JanetConfig) CSourceFile {
    const write_file = WriteFileBridge.init(bootstrap(b, config), config);
    return .{
        .source = .{
            .write_file = .{
                .step = write_file,
                .basename = "janet.c",
            },
        },
        .args = &[_][]const u8{"-fno-sanitize=undefined"},
    };
}

/// Return a `LibExeObjStep` corresponding to `janet_boot` in traditional Janet.
pub fn bootstrap(b: *Builder, config: JanetConfig) *LibExeObjStep {
    const exe = b.addExecutable("janet_boot", null);
    config.apply(exe);
    exe.defineCMacro("JANET_BOOTSTRAP=1");
    exe.linkLibC();
    const boot_path = std.fs.path.join(
        b.allocator,
        &[_][]const u8{ config.root_dir, "src", "boot" }
    ) catch unreachable;
    const core_path = std.fs.path.join(
        b.allocator,
        &[_][]const u8{ config.root_dir, "src", "core" },
    ) catch unreachable;
    for ([_][]const u8{ boot_path, core_path }) |path| {
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch unreachable;
        defer dir.close();
        var iter = dir.iterate();
        while (iter.next() catch unreachable) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".c")) {
                exe.addCSourceFile(
                    std.fs.path.join(
                        b.allocator,
                        &[_][]const u8{ path, entry.name },
                    ) catch unreachable,
                    &[_][]const u8{"-fno-sanitize=undefined"},
                );
            }
        }
    }
    return exe;
}

/// A step that bridges LibExeObjStep and WriteFileStep by capturing the bytes
/// of LibExeObjStep and injecting them into WriteFileStep. Used for generating
/// the amalgamate source file.
const WriteFileBridge = struct {
    write_file: WriteFileStep,
    config: JanetConfig,
    step: Step,

    /// Create a `WriteFileStep` from a `LibExeObjStep`. The `WriteFileStep` will
    /// write the contents of the executable stdout to file named `.janet.c`.
    fn init(boot: *LibExeObjStep, config: JanetConfig) *WriteFileStep {
        const b = boot.builder;
        const self = b.allocator.create(WriteFileBridge) catch unreachable;
        self.step = Step.init(.Custom, "WriteFileBridge", b.allocator, make);
        self.step.dependOn(&boot.step);
        self.write_file = WriteFileStep.init(b);
        self.write_file.add("janet.c", &[_]u8{});
        self.write_file.step.dependOn(&self.step);
        self.config = config;
        return &self.write_file;
    }

    /// After the executable is built, run it and pipe output into the WriteFileStep.
    fn make(step: *Step) !void {
        const self = @fieldParentPtr(WriteFileBridge, "step", step);
        const boot = @fieldParentPtr(LibExeObjStep, "step", step.dependencies.items[0]);
        const child = try std.ChildProcess.init(
            &[_][]const u8{ boot.getOutputPath(), self.config.root_dir },
            boot.builder.allocator,
        );
        child.stdin_behavior = .Close;
        child.stdout_behavior = .Pipe;
        defer child.deinit();
        try child.spawn();
        if (child.stdout.?.reader().readAllAlloc(boot.builder.allocator, 10_000_000)) |output| {
            const result = try child.wait();
            if (result != .Exited or result.Exited != 0) {
                std.log.err("janet_boot exit: {}", .{result});
                std.os.exit(1);
            }
            self.write_file.files.items[0].bytes = output;
        } else |err| {
            _ = child.kill() catch {};
            return err;
        }
    }
};
