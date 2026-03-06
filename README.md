# plat-hs

Haskell eDSL for [Plat](https://github.com/user/plat) architecture design.

Write your software architecture as Haskell values. Get compile-time reference safety, runtime validation, and `.plat` file generation.

## Quick Example

```haskell
{-# LANGUAGE OverloadedStrings #-}
import Plat.Core
import Plat.Check
import Plat.Generate.Plat (render)

-- Layers
core        = layer "core"
interface   = layer "interface"   `depends` [core]
application = layer "application" `depends` [core, interface]
infra       = layer "infra"       `depends` [core, application, interface]

-- Domain model
order :: Decl 'Model
order = model "Order" core $ do
  field "id"     (customType "UUID")
  field "total"  decimal
  field "status" string

-- Port
orderRepo :: Decl 'Boundary
orderRepo = boundary "OrderRepository" interface $ do
  op "save"    ["order" .: ref order] ["err" .: error_]
  op "findById" ["id" .: customType "UUID"] ["order" .: ref order, "err" .: error_]

-- Use case
placeOrder :: Decl 'Operation
placeOrder = operation "PlaceOrder" application $ do
  input  "order" (ref order)
  output "err"   error_
  needs orderRepo    -- compile-time: only Decl 'Boundary accepted

-- Infrastructure
pgRepo :: Decl 'Adapter
pgRepo = adapter "PostgresOrderRepo" infra $ do
  implements orderRepo
  inject "db" (ext "*sql.DB")

-- Architecture
architecture :: Architecture
architecture = arch "my-service" $ do
  useLayers [core, application, interface, infra]
  registerType "UUID"
  declare order
  declare orderRepo
  declare placeOrder
  declare pgRepo

main :: IO ()
main = do
  let result = check architecture
  putStrLn $ show (length (violations result)) ++ " violations"
  putStrLn $ render architecture
```

## What plat-hs gives you

| Feature | Mechanism |
|---------|-----------|
| No typos in references | Haskell variable bindings |
| No `needs model` or `bind adapter adapter` | `Decl k` phantom types |
| No `field` inside `compose` | `DeclWriter k` phantom-parameterized monad |
| Layer dependency violations | `check` / V001 |
| Unresolved boundaries | `check` / W001 |
| Undefined type references | `check` / W002 |
| `.plat` file generation | `renderFiles` |
| Mermaid diagrams | `renderMermaid` |
| Markdown docs | `renderMarkdown` |
| CRUD generation, pattern comparison | Plain Haskell functions |

## Project Structure

```
src/Plat/
  Core.hs                 -- Public API re-export
  Core/
    Types.hs              -- AST: Decl k, Declaration, DeclItem, TypeExpr
    Builder.hs            -- DeclWriter k, ArchBuilder monads
    TypeExpr.hs           -- Type constructors, ref, (.:)
  Check.hs                -- check, checkIO, checkOrFail, prettyCheck
  Check/
    Class.hs              -- PlatRule type class, SomeRule, Diagnostic
    Rules.hs              -- Core rules: V001-V008, W001-W003
  Generate/
    Plat.hs               -- .plat renderer
    Mermaid.hs            -- Mermaid diagram generator
    Markdown.hs           -- Markdown document generator
  Ext/
    DDD.hs                -- value, aggregate, enum_, invariant
    CQRS.hs               -- command, query
    CleanArch.hs          -- entity, port, impl_ + preset layers
    Http.hs               -- controller, route
    DBC.hs                -- pre, post, assert_
    Flow.hs               -- step, policy, guard_
    Events.hs             -- event, emit, on_, apply_
    Modules.hs            -- domain, expose, import_
```

## Type Safety

`Decl k` is a phantom-tagged newtype over `Declaration`. The tag `k :: DeclKind` restricts which combinators are available:

```haskell
needs :: Decl 'Boundary -> DeclWriter 'Operation ()
-- needs order       -- compile error: Decl 'Model /= Decl 'Boundary
-- needs pgRepo      -- compile error: Decl 'Adapter /= Decl 'Boundary
   needs orderRepo   -- OK

bind :: Decl 'Boundary -> Decl 'Adapter -> DeclWriter 'Compose ()
-- bind pgRepo orderRepo  -- compile error: wrong order/types

field :: Text -> TypeExpr -> DeclWriter 'Model ()
-- field inside a boundary -- compile error: DeclWriter 'Boundary /= DeclWriter 'Model
```

For meta-programming, `decl :: Decl k -> Declaration` erases the phantom tag, and `declares :: [Declaration] -> ArchBuilder ()` accepts homogeneous lists.

## Validation Rules

| Code | Severity | Description |
|------|----------|-------------|
| V001 | Error | Layer dependency violation |
| V002 | Error | Layer cycle detected |
| V003 | Error | `needs` target is not a boundary |
| V004 | Error | Boundary contains adapter-specific items |
| V005 | Error | `bind` outside compose |
| V006 | Error | Declaration name conflicts with reserved keyword |
| V007 | Error | Adapter with `implements` doesn't cover boundary ops |
| V008 | Error | `bind` left-hand is not boundary or right-hand is not adapter |
| W001 | Warning | Boundary has no implementing adapter |
| W002 | Warning | Undefined type reference (excludes `ext`, reserved types) |
| W003 | Warning | `@path` file does not exist (IO check) |

Rules are composable:

```haskell
checkWith (coreRules ++ dddRules ++ cqrsRules) architecture
```

## Extensions

All extensions are thin wrappers: smart constructors + `meta` tags + optional rules.

| Module | Vocabulary |
|--------|-----------|
| `Plat.Ext.DDD` | `value`, `aggregate`, `enum_`, `invariant` |
| `Plat.Ext.CQRS` | `command`, `query` |
| `Plat.Ext.CleanArch` | `entity`, `port`, `impl_`, `wire`, preset layers |
| `Plat.Ext.Http` | `controller`, `route` |
| `Plat.Ext.DBC` | `pre`, `post`, `assert_` |
| `Plat.Ext.Flow` | `step`, `policy`, `guard_` |
| `Plat.Ext.Events` | `event`, `emit`, `on_`, `apply_` |
| `Plat.Ext.Modules` | `domain`, `expose`, `import_` |

## Tasks (mise)

```
mise run build    # Build the library
mise run test     # Run 114 tests
mise run check    # Build + test
mise run lint     # Build with -Werror
mise run repl     # GHCi with plat-hs
mise run clean    # Clean build artifacts
mise run watch    # Rebuild on file changes (requires entr)
```

## Requirements

- GHC >= 9.6 (recommended: 9.10+)
- `OverloadedStrings` (only required user extension)
- `DataKinds` (optional, for explicit `Decl 'Model` type annotations; included in GHC2024)

## Specification

- [plat-hs-spec-v0.6.md](plat-hs-spec-v0.6.md) -- current
- [plat-hs-spec-v0.5.md](plat-hs-spec-v0.5.md) -- previous
