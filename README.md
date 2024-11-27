A generational arena for Zig.

See [src/arena.zig](src/arena.zig) tests for usage.

To use, add to your build.zig.zon and then add this to your
build.zig:

```zig
const hyarena = b.dependency("hyoga-arena", .{});
exe.root_module.addImport("hyoga-arena", hyarena.module("hyoga-arena"));
```
