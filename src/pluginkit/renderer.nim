# A plugin kit for Nim, allowing developers to create and manage
# plugins in a modular and extensible way. 
#
# (c) 2026 George Lemon | MIT License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/pluginkit

import std/[httpcore, json, macros, tables]
import pkg/supranim/core/[request, response]
export request, response

macro newController*(name, body: untyped) =
  ## Defines a new controller procedure with the given name and body.
  ## 
  ## This macro is similar with the one in `supranim/controller.nim`
  ## but for plugins
  expectKind name, nnkIdent
  result =
    newProc(
      name = nnkPostfix.newTree(ident("*"), name),
      params = [
        newEmptyNode(),
        newIdentDefs(
          ident"req",
          nnkPtrTy.newTree(
            ident"Request"
          ),
          newEmptyNode()
        ),
        newIdentDefs(
          ident"res",
          nnkPtrTy.newTree(
            ident"Response"
          ),
          newEmptyNode()
        ),
      ],
      pragmas = nnkPragma.newTree(
        ident"exportc",
        ident"cdecl",
        ident"dynlib"
      ),
      body =
        nnkPragmaBlock.newTree(
          nnkPragma.newTree(ident"gcsafe"),
          body
        )
    )

template ctrl*(name, body: untyped) =
  ## An alias for `newController` macro to define controller procedures
  ## in plugins.
  newController(name, body)

template render*(view: string, layout: string = "base",
                  httpCode = Http200, local: JsonNode = nil): untyped =
  ## Renders a Tim template and sends it as an HTTP response.
  discard

proc params*(req: ptr Request): lent Table[string, string] =
  ## Returns the route parameters from `Request`
  req.routeParams