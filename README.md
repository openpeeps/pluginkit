<p align="center">
  A plugin kit for creating and managing plugins in your 👑 Nim applications.<br>
</p>

<p align="center">
  <code>nimble install pluginkit</code>
</p>

<p align="center">
  <a href="https://github.com/">API reference</a><br>
  <img src="https://github.com/openpeeps/pluginkit/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/openpeeps/pluginkit/workflows/docs/badge.svg" alt="Github Actions">
</p>

## 😍 Key Features

- **Dynamic Plugin Loading** - Dynamic libraries (`.so`, `.dll`, `.dylib`) using Nim’s `std/dynlib`
- **Stable Plugin ABI** - C-compatible manifest structure and exported entry points (`plugin_get_manifest`, `plugin_init`, `plugin_deinit`)
- **Plugin Metadata & Manifest**, including name, version, author, description, license, URL, and permissions
- **Plugin Lifecycle Management** with `onload` and `onunload` callbacks for initialization and cleanup
- Permission System to control plugin capabilities and API access
- Macro-based Plugin Definition
- Semantic Versioning Support  
- **Callbacks & Extensible Manager**
- **Cross-platform** support for dynamic libraries on Windows, Linux, and macOS.

## Examples

### Creating a Simple Plugin
Here is an example creating a simple plugin that logs a message when initialized:
```nim
import pluginkit

plugin helloworld, {
  name: "HelloWorld",
  author: "George Lemon",
  description: "A simple plugin that prints 'Hello, world!' to the console.",
  license: "MIT",
  url: "https://github.com/openpeeps/pluginkit",
  permissions: {permissionEmitEvents, permissionHandleRequests}
}:
  onload do:
    # This code will be executed when the plugin is loaded.
    echo "Hello, world!"
  onunload do:
    # This code will be executed when the plugin is unloaded.
    echo "Goodbye, world!"
```

Now, compile this plugin as a dynamic library and load it in your application using the `PluginManager`:
```bash
nim c --app:lib helloworld.nim
```

## Initializing the Plugin Manager
To use the `PluginManager`, you can initialize it in your application like this:
```nim
import pluginkit

var manager = PluginManager(
  callbacks: PluginManagerCallbacks(
    onPluginLoaded: proc (plugin: Plugin) =
      echo plugin.getId()
      echo "Plugin loaded: ", plugin.getName, " by ", plugin.getAuthor
    ,onPluginUnloaded: proc (plugin: Plugin) =
      echo "Plugin unloaded: ", plugin.getName
    ,onPluginError: proc (plugin: Plugin, error: string) =
      echo "Error in plugin ", plugin.getName, ": ", error
))

for path in walkFiles("./plugins):
  if path.endsWith(".so") or path.endsWith(".dll") or path.endsWith(".dylib"):
     manager.load(path)
```

### Todo
- [ ] Add support for version constraints
- [ ] Extend the permission system with more granular permissions and API exposure
- [ ] Implement plugin dependency management
- [ ] Unit tests for plugin loading, lifecycle events, and permission checks
- [ ] Example plugins demonstrating various features and use cases

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/pluginkit)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/pluginkit)
- 😎 [Get €20 in cloud credits from Hetzner](https://hetzner.cloud/?ref=Hm0mYGM9NxZ4)

### 🎩 License
MIT license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.
