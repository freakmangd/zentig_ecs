# Installation

## Local

After you've created your project with `zig init-exe`

```cmd
cd dir_with_build_dot_zig_file
git clone https://github.com/freakmangd/zentig_ecs.git lib/zentig_ecs
```

Add this to your `build.zig`
```zig
// Other libraries may use `ztg` for linking
// or you can discard it.
const ztg = @import("lib/zentig_ecs/build.zig").addAsLocalModule(.{
    .name = "zentig",
    .path_to_root = "lib/zentig_ecs/",
    .build = b,
    .exe = exe,
    .target = target,
    .optimize = optimize,
});
```

## Package Manager
#### Skip to "Including the module in your project" if you are familiar with the package manager.

The zig package manager is in very early stages so this is a (semi) convoluted process!

### Getting the full commit SHA of latest master

Run this command in your terminal: `git ls-remote https://github.com/freakmangd/zentig_ecs HEAD`.

The output will be something like `[LONG STRING OF CHARACTERS AND NUMBERS] HEAD`.

The "long string of characters and numbers" is the full commit SHA of the latest master branch.

### Adding to your dependencies

To your `build.zig.zon` add three lines in the `dependencies` object.
(If you dont have a `build.zig.zon` just create one next to your `build.zig` file)
```zig
.{
    .name = "Your project",
    .version = "0.1.0",
    .dependencies = .{
        // Add this
        .zentig = .{
            .url = "https://github.com/freakmangd/zentig_ecs/archive/[FULL COMMIT SHA].tar.gz",
        },
        // ...
    },
}
```

Then run `zig build` to get the `hash`, it will be in a compile error note.
Then update your `build.zig.zon` to include the `hash` next to the `url` field.
```zig
.url = "https://github.com/freakmangd/zentig_ecs/archive/[FULL COMMIT SHA].tar.gz",
// add here
.hash = "[HASH ZIG GAVE YOU]",
```

### Including the module in your project

Now you can include the module in your project, in your `build.zig` file:
```zig
const zentig_dep = b.dependency("zentig", .{
    .target = target,
    .optimize = optimize,
});
const zentig_mod = zentig_dep.module("zentig");
exe.addModule("zentig", zentig_mod);
```
