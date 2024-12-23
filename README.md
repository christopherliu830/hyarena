A generational arena for Zig.

See [src/slotmap.zig](src/slotmap.zig) tests for usage.

To use, add to your build.zig.zon and then add this to your
build.zig:

```zig
const hysm = b.dependency("hyoga-slotmap", .{});
exe.root_module.addImport("hyoga-slotmap", hyarena.module("hyoga-slotmap"));
```
