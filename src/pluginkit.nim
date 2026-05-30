# A plugin kit for Nim, allowing developers to create and manage
# plugins in a modular and extensible way. 
#
# (c) 2026 George Lemon | MIT License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/pluginkit

## This module implements an advanced plugin system for Nim,
## allowing developers to create and manage plugins that can extend
## the functionality of their applications in a modular and scalable way.
## 
## Use `-d:pluginkit_debug` to enable debug output for the generated plugin code.

import std/[tables, os, strutils, sequtils, options,
              macros, dynlib, macrocache, strformat]

import pkg/[semver, openparser/json]
import pkg/checksums/sha1

import ./pluginkit/[nanoid, readers]
export `%*`, dynlib, json

type
  PluginType* = enum
    ## Enumeration representing
    pluginTypeAuthentication
    pluginTypeDatabase
    pluginTypeAnalytics
    pluginTypePayment
    pluginTypeNotification
    pluginTypeOther

  PluginStatus* = enum
    ## Representation of the status of a plugin, indicating
    ## whether it is active or inactive
    pluginStatusUnload
      # The plugin is not loaded into the system. It is inactive and cannot perform any actions
    pluginStatusLoaded
      # The plugin is loaded into the system but is not active. It may be in a state of
      # initialization or waiting for certain conditions to be met before it can become active
    pluginStatusActive
      # The plugin is fully active and operational. It can perform its intended
      # functions and interact with the system
    pluginStatusInvalid
      # The plugin is in an invalid state, which could be due to a loading error,
      # incompatibility with the system, or other issues that prevent it from
      # functioning properly

  PluginPermission* = enum
    ## Enumeration representing permissions that a plugin can request.
    reqNil
    reqDBFullAccess
    reqDBReadOnly
    reqDBWriteOnly
    reqEvents
    reqRoutes
    reqAccessConfig
    reqAccessSessions
  
  PluginPermissionMask* = uint64
    ## A type representing a bitmask of plugin permissions, allowing for efficient
    ## storage and checking of multiple permissions for a plugin.

  PluginSystemVersion* = object
    ## The structure representing the version of the plugin system
    ## and the minimum required version for a plugin to be compatible with.
    systemVersion: semver.Version
      ## The version of the plugin system, following semantic versioning.
    nimVersion: semver.Version
      ## The version of Nim required for the plugin to be
      ## compatible with the plugin system.
  
  NanoID* = string
    ## A type representing a unique identifier for plugins,
    ## generated using the NanoID algorithm.

  PluginManifest* {.bycopy.} = object
    ## The structure representing the manifest of a plugin, containing
    ## metadata about the plugin such as its name, author, description,
    ## license, URL, version, and the permissions it requests.\
    abiVersion*: uint32
      ## The ABI version of the plugin, used to ensure compatibility between
      ## the plugin and the plugin system. This allows the plugin manager
      ## to check if a plugin is compatible with the current version of the
      ## plugin system before loading it.
    name*, author*, description*, license*, url*: cstring
      ## Metadata fields for the plugin, including its name, author, description,
      ## license, and URL. These fields provide information about the plugin and
      ## can be used for display purposes in a plugin manager or marketplace.
    version*: cstring
      ## The version of the plugin, following semantic versioning.
    nimVersion*: cstring
      ## The version of Nim required for the plugin to be compatible with the plugin system.
    permissions*: PluginPermissionMask
      ## A bitmask representing the permissions that the plugin requests. This allows
      ## for efficient storage and checking of multiple permissions for a plugin.

  plugin_get_manifest_fn* = proc(outManifest: ptr PluginManifest): cint {.cdecl.}
  plugin_init_fn* = proc(): cint {.cdecl.}
  plugin_deinit_fn* = proc() {.cdecl.}
  plugin_event_load_fn* = proc(): cstring {.cdecl.}

  plugin_event_fn* = proc() {.cdecl.}

  PluginDatabaseSchemas* = JsonNode
    ## Custom schemas defined by the plugin for its database models

  Plugin* {.inheritable.} = ref object
    ## The structure representing a plugin.
    id: NanoID
      # A unique identifier for the plugin, generated using
      # the NanoID. This ID is created at load time everytime the app
      # starts up and is used for internal management of plugins.
    runId*: Option[NanoID]
      ## A persistent unique identifier for the plugin, generated using NanoID
      ## at the time of the plugin's installation. This ID is stored in the database and
      ## is used to track the plugin across application restarts, allowing for consistent
      ## identification of the plugin
    `type`*: PluginType
      ## The type of the plugin, which can be used to categorize plugins
      ## and determine how they should be loaded and executed within the application.
      ## For example, a plugin could be of type "authentication", "database", "analytics", etc.
    status: PluginStatus
      # The current status of the plugin, indicating whether
      # it is active, loaded, or unloaded
    manifest: PluginManifest
      ## The manifest of the plugin, containing metadata and permissions information.
      ## This is used to manage the plugin's lifecycle and determine its capabilities
      ## within the application.
    name, author, description, license, url: string
      # Metadata about the plugin, such as its name, author, description, license, and URL.
    schemas: string
      # The requirements for the plugin, which can include
      # dependencies on other plugins, required configurations,
      # or other conditions that must be met for the plugin to function properly.
    permissions: set[PluginPermission]
      ## The set of permissions that the plugin requests. This is used to determine
      ## what actions the plugin is allowed to perform within the application.
    version: semver.Version
      ## The version of the plugin, following semantic versioning.
    systemVersion: PluginSystemVersion
      # The version of the plugin system that the plugin is compatible with.
    libHandle: LibHandle
      # The handle to the loaded dynamic library for the plugin, used for managing
      # the plugin's lifecycle and unloading it when necessary.
    initFn: plugin_init_fn
      # The function pointer to the plugin's initialization function,
      # which will be called when the plugin is loaded to perform any necessary setup.
    deinitFn: plugin_deinit_fn
      # The function pointer to the plugin's deinitialization function,
      # which will be called when the plugin is unloaded to perform any necessary cleanup.
    filepath: string
      # The file path from which the plugin was loaded, used for reference
      # and management purposes.
    staticTemplates*: TableRef[string, string]
      # A table of static files that were bundled into the plugin at
      # compile time using the `serializeTemplates` macro from `pluginkit/readers`
    registerRoutes*: JsonNode
      # A JSON node containing the routes that were registered
      # by the plugin using the `registerRoutes` macro
    staticFiles: TableRef[string, string]
      # A table of static files that were bundled into the plugin at
      # compile time using the `embedStaticFiles` macro from `pluginkit/readers`

#
# Utilities
#
const
  PluginAbiVersion* = 1'u32
  permDBFullAccess*   = PluginPermissionMask(1'u64 shl ord(reqDBFullAccess))
  permDBReadOnly*     = PluginPermissionMask(1'u64 shl ord(reqDBReadOnly))
  permDBWriteOnly*    = PluginPermissionMask(1'u64 shl ord(reqDBWriteOnly))
  permEmitEvents*     = PluginPermissionMask(1'u64 shl ord(reqEvents))
  permHandleRoutes* = PluginPermissionMask(1'u64 shl ord(reqRoutes))
  permAccessConfig*   = PluginPermissionMask(1'u64 shl ord(reqAccessConfig))
  permAccessSessions* = PluginPermissionMask(1'u64 shl ord(reqAccessSessions))

proc hashIdentifier*(id: string): string =
  # Hash the plugin identifier using SHA-1 and convert
  # it to a lowercase hexadecimal string.
  toLowerAscii($(secureHash(id)))

proc toPermissionMask*(s: set[PluginPermission]): PluginPermissionMask =
  ## Converts a set of PluginPermission values into a PluginPermissionMask
  ## bitmask for efficient storage and checking.
  result = 0
  for p in s:
    if p != reqNil:
      result = result or PluginPermissionMask(1'u64 shl ord(p))

proc toPermissionSet*(m: PluginPermissionMask): set[PluginPermission] =
  ## Converts a PluginPermissionMask bitmask back into a set of
  ## PluginPermission values for easier readability and usage in the application.
  for p in PluginPermission:
    if p != reqNil and (m and PluginPermissionMask(1'u64 shl ord(p))) != 0:
      result.incl p

proc cstrToString*(cs: cstring): string {.inline.} =
  if cs != nil: $cs else: ""

when compileOption("app", "lib"):
  #
  # The Plugin structure represents a plugin in the system, containing
  # all the necessary information about the plugin, such as its type,
  #
  var onLoadBlockStmt {.compileTime.}: NimNode = newStmtList()
  var onLoadstaticTemplates {.compileTime.}: NimNode = newStmtList()

  macro onUnload*(stmt: typed) =
    result = stmt

  macro onInit*(stmt: typed) =
    ## The `onInit` macro is used to define the initialization block for a plugin.
    ## This block contains the code that will be executed when the plugin is loaded,
    ## allowing the plugin to perform any necessary setup, such as registering
    ## routes, initializing state, or other tasks specific to the plugin's
    ## functionality
    result = stmt
    for n in result:
      case n.kind:
      of nnkLetSection:
        # echo n[0][2].repr
        onLoadBlockStmt.add(n[0][2])
      else: discard

  macro plugin*(id, config: untyped, init: typed) =
    ## Macro for defining a plugin. It takes an identifier, a configuration
    ## block, and an initialization block. The configuration block is used
    ## to set up the plugin's metadata and permissions, while the initialization
    ## block contains the code that will be executed when the plugin is loaded.
    expectKind(id, nnkIdent) # the id should be an identifier
    expectKind(config, nnkTableConstr) # the config should be a table constructor
    var name, author, description, license, url, version: string
    var permissionsExpr: PluginPermissionMask = 0'u64

    proc addPermNode(n: NimNode) =
      case n.kind
      of nnkIdent, nnkSym:
        let p = parseEnum[PluginPermission](n.strVal)
        if p != reqNil:
          permissionsExpr = permissionsExpr or PluginPermissionMask(1'u64 shl ord(p))
      of nnkBracket, nnkCurly, nnkPar:
        for it in n:
          addPermNode(it)
      else:
        error("Invalid permissions format. Use ident, [..], or {..}. Got: " & $n.kind, n)

    for field in config:
      expectKind(field, nnkExprColonExpr)
      if field[0].eqIdent"name":
        name = $field[1]
      elif field[0].eqIdent"author":
        author = $field[1]
      elif field[0].eqIdent"description":
        description = $field[1]
      elif field[0].eqIdent"license":
        license = $field[1]
      elif field[0].eqIdent"url":
        url = $field[1]
      elif field[0].eqIdent"version":
        version = $field[1]
      elif field[0].eqIdent"permissions":
        # parse enumerable permissions into a set of PluginPermission values
        addPermNode(field[1])
      else:
        error("Unknown field in plugin config: " & $field[0])

    # parse the `init` and try retrieve the `onload`, `onunload`, and `oninit` blocks from it
    expectKind(init, nnkStmtList)
    var onloadBlock, loadStaticTemplates,
      loadRoutes, loadNavigation, onunloadBlock, oninitBlock: NimNode
    if onLoadBlockStmt.len > 0:
      onloadBlock =
        newProc(
          ident"plugin_event_load",
          params = [
            ident("cstring")
          ],
          body = newCall(
            ident("cstring"),
            onLoadBlockStmt
          )
        )
    else:
      onloadBlock = newStmtList()

    result = newStmtList()

    # if plugin provides a `staticTemplates` item, generate
    # the `plugin_event_load_static_files` function to return the static templates
    if PluginStorage.hasKey("staticTemplates"):
      loadStaticTemplates = newProc(
        nnkPostfix.newTree(
          ident("*"),
          ident"plugin_event_load_static_files",
        ),
        params = [
          ident("cstring"),
        ],
        body = newStmtList().add(ident"staticTemplates")
      )
      
      # inject static data for templates
      let staticTemplatesTable = PluginStorage["staticTemplates"]
      add result, quote do:
        const staticTemplates {.inject.} = toJson(toTable(`staticTemplatesTable`))
          # inject the static templates data into the plugin code as a constant,
          # allowing the plugin manager to retrieve the templates when the plugin is loaded
    else:
      loadStaticTemplates = newStmtList()

    if PluginStorage.hasKey("routes"):
      # if the plugin has registered routes using the `registerRoutes` macro,
      # we can generate the necessary code to load those routes when the plugin is loaded
      loadRoutes = newProc(
        nnkPostfix.newTree(
          ident"*",
          ident"plugin_event_load_routes",
        ),
        params = [
          ident("cstring"),
        ],
        body = newStmtList().add(
          newCall(
            ident"toJson",
            ident"routes"
          )
        )
      )

      let routesTable = PluginStorage["routes"]
      add result, quote do:
        let routes {.inject.} = fromJson(`routesTable`)
          # inject the routes data into the plugin code as a constant,
          # allowing the plugin manager to retrieve the routes when the plugin is loaded
    else:
      loadRoutes = newStmtList()

    # if plugin defines a `navigation` item, generate the
    # `plugin_event_load_navigation` function to return the
    # navigation data to the plugin manager
    if PluginStorage.hasKey("navigation"):
      loadNavigation = newProc(
        ident"plugin_event_load_navigation",
        params = [
          ident("cstring"),
        ],
        body = newStmtList().add(ident"navigation")
      )

      # inject static data for navigation
      let navigationTable = PluginStorage["navigation"]
      add result, quote do:
        const navigation {.inject.} = `navigationTable`
    else:
      loadNavigation = newStmtList()

    # if plugin defines other handlers add them to the generated code
    var otherHandlers = newStmtList()
    if PluginStorage.hasKey("otherHandlers"):
      otherHandlers = PluginStorage["otherHandlers"]

    add result, quote do:
      var gManifest {.inject.} = PluginManifest(
        abiVersion: PluginAbiVersion,
        name: cstring(`name`),
        author: cstring(`author`),
        description: cstring(`description`),
        license: cstring(`license`),
        url: cstring(`url`),
        version: cstring(`version`),
        permissions: `permissionsExpr`,
        nimVersion: NimVersion
      )

      proc NimMain {.cdecl, importc.}
      
      {.push exportc, cdecl, dynlib.}
      proc plugin_get_manifest*(outManifest {.inject.}: ptr PluginManifest): cint =
        ## This function is called by the plugin manager to retrieve the
        ## plugin's manifest information. The plugin should fill the provided
        ## PluginManifest structure with its metadata and permissions information.
        if outManifest.isNil: return 1
        outManifest[] = gManifest
        return 0

      proc plugin_init*(): cint =
        ## Perform any necessary initialization when the plugin is loaded.
        ## This can include setting up resources, initializing state,
        ## or other setup tasks specific to the plugin's functionality
        NimMain() # important for Nim runtime in dynamic lib
        return 0

      `onloadBlock`
      
      `loadStaticTemplates`
      `loadRoutes`
      `loadNavigation`
      `otherHandlers`

      proc plugin_deinit*() =
        ## Perform any necessary cleanup when the plugin is unloaded. This can include
        ## freeing resources, closing connections, or other cleanup tasks
        ## specific to the plugin's functionality
        GC_FullCollect()
      {.pop.}
    
    when defined(pluginkit_debug):
      echo result.repr
    echo result.repr
else:
  #
  # API for PluginManager and Plugin structures
  #
  type
    PluginManagerCallbacks* = object
      ## The PluginManagerCallbacks structure defines the callbacks that can be
      ## registered with the PluginManager. These callbacks allow plugins to
      ## respond to various events in the plugin lifecycle, such as when a plugin
      ## is loaded, unloaded, or when an error occurs.
      onLoad*: proc (plugin: Plugin)
        ## Callback that is called when a plugin is successfully loaded.
      onUnload*: proc (plugin: Plugin)
        ## Callback that is called when a plugin is successfully unloaded.
      onError*: proc (plugin: Plugin, error: string)
        ## Callback that is called when an error occurs during plugin loading or unloading.

    PluginManager* = ref object
      ## The PluginManager is responsible for managing the lifecycle of plugins,
      ## including loading, unloading, and executing plugins. It maintains a registry
      ## of available plugins and their statuses.
      plugins: Table[string, Plugin]
        # A table mapping plugin names to their corresponding Plugin objects.
      pluginIdentifiers: Table[string, string]
        # A table mapping their unique hashed identifiers to their names,
        # allowing for quick lookup and management of plugins.
      callbacks*: PluginManagerCallbacks
        ## The callbacks registered with the PluginManager, allowing it to notify plugins
        ## of lifecycle events such as loading, unloading, and errors.

    PluginManagerError* = object of CatchableError

  proc unload*(manager: PluginManager|ptr PluginManager, id: string) =
    ## Unloads a plugin by its unique id.
    if not manager.plugins.contains(id):
      raise newException(PluginManagerError, "Plugin not loaded: " & id)

    let plugin = manager.plugins[id]

    if plugin.deinitFn != nil:
      plugin.deinitFn()

    if plugin.libHandle != nil:
      unloadLib(plugin.libHandle)

    plugin.status = pluginStatusUnload
    manager.plugins.del(id)
    if manager.pluginIdentifiers.contains(id):
      manager.pluginIdentifiers.del(id)

    if manager.callbacks.onUnload != nil:
      manager.callbacks.onUnload(plugin)

  proc loadPlugin(manager: PluginManager|ptr PluginManager, plugin: Plugin) =
    # Loads a plugin into the system. This procedure will add the plugin to the
    if manager.plugins.contains(plugin.id):
      raise newException(PluginManagerError, "Plugin already loaded: " & plugin.name)
    
    let eventLoadFn = cast[plugin_event_load_fn](plugin.libHandle.symAddr("plugin_event_load"))
    if eventLoadFn != nil:
      let deps = cstrToString(eventLoadFn())
      plugin.schemas = deps

    if manager.callbacks.onLoad != nil:
      manager.callbacks.onLoad(plugin)

    manager.plugins[plugin.id] = plugin
    manager.pluginIdentifiers[plugin.id] = plugin.name

  proc load*(manager: PluginManager|ptr PluginManager, path: string): NanoID =
    ## Loads a plugin from the specified path. This procedure will attempt to
    ## load the plugin's dynamic library, initialize the plugin, and add it to
    ## the manager's registry.
    if not fileExists(path):
      raise newException(PluginManagerError, "Plugin file not found: " & path)
    
    # try to load the plugin library and initialize the plugin
    let lib: LibHandle = dynlib.loadLib(path)
    if lib == nil:
      raise newException(PluginManagerError, "Failed to load plugin library: " & path)

    let getManifest = cast[plugin_get_manifest_fn](lib.symAddr("plugin_get_manifest"))
    let initFn = cast[plugin_init_fn](lib.symAddr("plugin_init"))
    let deinitFn = cast[plugin_deinit_fn](lib.symAddr("plugin_deinit"))

    if getManifest.isNil or initFn.isNil:
      unloadLib(lib)
      raise newException(PluginManagerError, "Missing required symbols in plugin: " & path)

    var mf: PluginManifest
    if getManifest(addr mf) != 0:
      unloadLib(lib)
      raise newException(PluginManagerError, "plugin_get_manifest failed: " & path)

    if mf.abiVersion != PluginAbiVersion:
      unloadLib(lib)
      raise newException(PluginManagerError,
        "Plugin ABI mismatch. Expected " & $PluginAbiVersion & ", got " & $mf.abiVersion)

    let versionStr = mf.version
    var parsedVersion: semver.Version
    if versionStr.len > 0:
      try:
        parsedVersion = semver.parseVersion($versionStr)
      except CatchableError:
        unloadLib(lib)
        raise newException(PluginManagerError,
          "Invalid plugin version format: " & $versionStr)
    else:
      unloadLib(lib)
      raise newException(PluginManagerError, "Plugin version is required: " & path)
    
    let id = nanoid.generate(size = 32)
    let pluginName = cstrToString(mf.name)

    if mf.nimVersion.len > 0:
      var parseReqNimVersion: semver.Version
      try:
        parseReqNimVersion = semver.parseVersion($mf.nimVersion)
      except CatchableError:
        unloadLib(lib)
        raise newException(PluginManagerError, "Invalid plugin Nim version format: " & $mf.nimVersion)
      let currentNimVersion = semver.parseVersion(NimVersion)
      if currentNimVersion < parseReqNimVersion:
        unloadLib(lib)
        raise newException(PluginManagerError,
          "Plugin `$1` requires Nim version $2 or higher. Current version $3" % [
            pluginName, $parseReqNimVersion, $currentNimVersion
          ])

    var reqPermissions = toPermissionSet(mf.permissions)
    if reqPermissions.len == 0:
      reqPermissions = {reqNil}

    let plugin = Plugin(
      id: hashIdentifier(pluginName & $versionStr),
      `type`: pluginTypeOther,
      status: pluginStatusLoaded,
      name: pluginName,
      author: cstrToString(mf.author),
      description: cstrToString(mf.description),
      license: cstrToString(mf.license),
      url: cstrToString(mf.url),
      permissions: reqPermissions,
      version: parsedVersion,
      libHandle: lib,
      initFn: initFn,
      deinitFn: deinitFn,
      filepath: path
    )
    manager.loadPlugin(plugin)
    result = id

  proc activate*(manager: PluginManager|ptr PluginManager, id: string) =
    ## Activates a plugin by its unique identifier. This procedure will check
    ## if the plugin is loaded and then call its initialization function to
    ## make it active within the system
    if not manager.plugins.contains(id):
      raise newException(PluginManagerError, "Plugin not found: " & id)

    let plugin = manager.plugins[id]
    if plugin.initFn.isNil:
      raise newException(PluginManagerError, "plugin_init symbol is nil for: " & plugin.name)

    let rc = plugin.initFn()
    if rc != 0:
      # If initialization fails, we should unload the plugin and mark it as invalid
      plugin.status = pluginStatusInvalid
      if manager.callbacks.onError != nil:
        manager.callbacks.onError(plugin, "plugin_init failed with code " & $rc)
      raise newException(PluginManagerError, "Failed to activate plugin: " & plugin.name)
    plugin.status = pluginStatusActive
    
    let eventInitFn = cast[plugin_event_fn](plugin.libHandle.symAddr("plugin_event_init"))
    if eventInitFn != nil:
      eventInitFn()

  #
  # Plugin public API
  #
  iterator plugins*(manager: PluginManager|ptr PluginManager): Plugin =
    ## An iterator that yields all the currently loaded plugins in the manager.
    for p in manager.plugins.values:
      yield p

  proc getHandle*(plugin: Plugin): LibHandle =
    ## Returns the handle to the loaded dynamic library for the plugin. This can be used
    ## for advanced operations such as directly calling functions from the plugin's library
    ## or for debugging purposes.
    plugin.libHandle

  proc hasPlugin*(manager: PluginManager|ptr PluginManager, id: NanoID): bool =
    ## Checks if a plugin with the given unique
    ## identifier is currently loaded in the manager
    manager.plugins.hasKey(id)

  proc getPlugin*(manager: PluginManager|ptr PluginManager, id: NanoID): Plugin =
    ## Retrieves a plugin by its unique identifier. If the plugin is not found,
    ## an exception is raised.
    if unlikely(not manager.plugins.hasKey(id)):
      raise newException(PluginManagerError, "Plugin not found: " & id)
    manager.plugins[id]

  proc getStatus*(plugin: Plugin): PluginStatus =
    ## Returns the current status of the plugin, indicating whether it is active,
    ## loaded, unloaded, or in an invalid state.
    plugin.status

  proc getId*(plugin: Plugin): lent string =
    ## Returns the unique identifier of the plugin. This identifier is generated
    ## using a hash of the plugin's path, name, and version, ensuring that each
    ## plugin can be uniquely identified and referenced within the system.
    plugin.id

  proc getName*(plugin: Plugin): lent string =
    ## Returns the name of the plugin, as specified in its manifest. This is used
    ## for display purposes and to identify the plugin within the system.
    plugin.name
  
  proc getAuthor*(plugin: Plugin): lent string =
    ## Returns the author of the plugin, as specified in its manifest. This provides
    ## information about who created the plugin and can be used for
    ## attribution and support purposes.
    plugin.author
  
  proc getDescription*(plugin: Plugin): lent string =
    ## Returns the description of the plugin, as specified in its manifest. This provides
    ## information about what the plugin does and can be used to inform
    ## users about the plugin's functionality.
    plugin.description

  proc getLicense*(plugin: Plugin): lent string =
    ## Returns the license of the plugin, as specified in its manifest. This provides
    ## information about the legal terms under which the plugin is distributed and
    ## can be used for compliance purposes.
    plugin.license
  
  proc getURL*(plugin: Plugin): lent string =
    ## Returns the URL of the plugin, as specified in its manifest. This can provide
    ## a link to the plugin's homepage, documentation, or source code repository
    ## for users who want to learn more about the plugin or seek support.
    plugin.url
  
  proc getVersion*(plugin: Plugin): string =
    ## Returns the version of the plugin, as specified in its manifest. This follows
    ## semantic versioning and can be used to manage plugin updates and compatibility.
    $(plugin.version)
    
  proc getPermissions*(plugin: Plugin): set[PluginPermission] =
    ## Returns the set of permissions that the plugin requests, as specified
    ## in its manifest. This can be used to determine what actions the plugin
    ## is allowed to perform within the application and to inform users
    ## about the plugin's capabilities and potential security implications.
    plugin.permissions

  proc getSchemas*(plugin: Plugin): lent string =
    ## Returns the custom database schemas defined by the plugin, if any. This allows
    ## the plugin to define its own database models and structures that can be used
    ## within the application, enabling plugins to manage their own data and integrate
    plugin.schemas

  proc getFilepath*(plugin: Plugin): lent string =
    ## Returns the file path from which the plugin was loaded. This can be used for
    ## reference and management purposes, allowing the application to track where
    ## each plugin is located on the filesystem.
    plugin.filepath