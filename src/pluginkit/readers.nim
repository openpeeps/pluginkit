# A plugin kit for Nim, allowing developers to create and manage
# plugins in a modular and extensible way. 
#
# (c) 2026 George Lemon | MIT License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/pluginkit

import std/[os, strutils, macros, macrocache, json]

const PluginStorage* = CacheTable"PluginKitStaticReaders"
  ## This cache table stores the contents of files read at compile-time.

macro registerTemplates*(basepath, path: static string) =
  ## A macro that reads template file contents at compile time
  ## and stores them in a cache table, so they can be accessed/processed at runtime
  ## via PluginManager's API.
  var tableNode = newNimNode(nnkTableConstr)
  for fpath in walkDirRec(basepath / path):
    let id = fpath.replace(basepath / path, "")[1..^1] # remove the base path and leading slash
    tableNode.add(nnkExprColonExpr.newTree(
      newLit(id),
      newLit(staticRead(fpath))
    ))
  PluginStorage["staticTemplates"] = tableNode

macro register*(key: untyped, config: static JsonNode) =
  ## A macro that serializes a Nim data structure (e.g. a table or object)
  ## into a JSON string at compile time and stores it in a cache table, so it can be
  ## accessed/processed at runtime via PluginManager's API.
  expectKind(key, nnkIdent)
  if config.kind notin {JArray, JObject}:
    error("Config must be a JSON object or array literal")
  PluginStorage[key.strVal] = newLit($config)

macro embedStaticFiles*(basepath: static string, paths: static openArray[(string, string)]) =
  ## A macro that reads file contents at compile and bundles them into the
  ## plugin binary as a static resource, so they can be accessed/processed at runtime
  ## via PluginManager's API.
  var tableNode = newNimNode(nnkTableConstr)
  for path in paths:
    if fileExists(basepath / path[1]):
      let content = staticRead(basepath / path[1])
      tableNode.add(nnkExprColonExpr.newTree(
        newLit(path[0]),
        newLit(content)
      ))
    else:
      # if the file doesn't exist, most probably is a directory, 
      # so we will walk it recursively and embed all the files inside it as static resources
      for fpath in walkDirRec(basepath / path[1]):
        let id = fpath.replace(basepath / path[1], "")[1..^1] # remove the base path and leading slash
        tableNode.add(nnkExprColonExpr.newTree(
          newLit(id),
          newLit(staticRead(fpath))
        ))
  PluginStorage["staticFiles"] = tableNode