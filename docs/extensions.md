# Extension Guide

## Design Principle

拡張は core の AST (`DeclItem`) を変更しない。すべて以下のパターンで実装する:

1. **Smart constructor**: core の宣言コンストラクタ (`model`, `boundary`, etc.) をラップし、`meta` タグを付与
2. **Query helpers**: `lookupMeta` を使って拡張固有のメタデータを問い合わせる関数
3. **Optional rules**: `PlatRule` instance を持つ検証ルール

```haskell
-- 1. Smart constructor
aggregate :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
aggregate name ly body = model name ly $ do
  meta "plat-ddd:kind" "aggregate"
  body

-- 2. Query helper
isAggregate :: Declaration -> Bool
isAggregate d = lookupMeta "plat-ddd:kind" d == Just "aggregate"

-- 3. Optional rule
data AggregateIdRule = AggregateIdRule
instance PlatRule AggregateIdRule where
  ruleCode _ = "DDD-V002"
  checkDecl _ _ d
    | isAggregate d, not (any isIdField (declBody d))
    = [Diagnostic Warning "DDD-V002" "aggregate should have an Id field" (declName d) Nothing]
    | otherwise = []
```

## Meta Naming Convention

```
plat-{extension}:{key}
plat-{extension}:{key}:{subkey}
```

例:
- `plat-ddd:kind` → `"value"` | `"aggregate"` | `"enum"`
- `plat-ddd:variant:Pending` → `"Pending"`
- `plat-http:route:PlaceOrder` → `"POST /orders"`
- `plat-events:emit:OrderPlaced` → `"OrderPlaced"`

## Extension Summary

### DDD (`Plat.Ext.DDD`)

| Constructor | Base | Meta tag |
|-------------|------|----------|
| `value` | `model` | `plat-ddd:kind = "value"` |
| `aggregate` | `model` | `plat-ddd:kind = "aggregate"` |
| `enum_` | `model` | `plat-ddd:kind = "enum"` + variant tags |
| `invariant` | (combinator) | `plat-ddd:invariant:{name} = {expr}` |

Rules: DDD-V001 (value no id), DDD-V002 (aggregate should have id)

### CQRS (`Plat.Ext.CQRS`)

| Constructor | Base | Meta tag |
|-------------|------|----------|
| `command` | `operation` | `plat-cqrs:kind = "command"` |
| `query` | `operation` | `plat-cqrs:kind = "query"` |

Helpers: `isCommand`, `isQuery`

### CleanArch (`Plat.Ext.CleanArch`)

Preset layers: `enterprise`, `application`, `interface`, `framework` (+ `cleanArchLayers`)

| Constructor | Base | Meta tag |
|-------------|------|----------|
| `entity` | `model` | `plat-cleanarch:kind = "entity"` |
| `usecase` | `operation` | `plat-cleanarch:kind = "usecase"` |
| `port` | `boundary` | `plat-cleanarch:kind = "port"` |
| `impl_` | `adapter` + `implements` | `plat-cleanarch:kind = "impl"` |
| `wire` | `compose` | `plat-cleanarch:kind = "wire"` |

### Http (`Plat.Ext.Http`)

| Constructor | Base | Meta tag |
|-------------|------|----------|
| `controller` | `adapter` | `plat-http:kind = "controller"` |
| `route` | (combinator) | `plat-http:route:{opName} = "{METHOD} {path}"` + inject |

`route` は meta にルート情報を記録しつつ、target operation を inject する。

### DBC (`Plat.Ext.DBC`)

| Constructor | Context | Meta tag |
|-------------|---------|----------|
| `pre` | `DeclWriter 'Operation` | `plat-dbc:pre:{name} = {expr}` |
| `post` | `DeclWriter 'Operation` | `plat-dbc:post:{name} = {expr}` |
| `assert_` | `DeclWriter k` (universal) | `plat-dbc:assert:{name} = {expr}` |

Rules: DBC-W001 (contracts without needs)

### Flow (`Plat.Ext.Flow`)

| Constructor | Base | Meta tag |
|-------------|------|----------|
| `step` | `operation` | `plat-flow:kind = "step"` |
| `policy` | `model` | `plat-flow:kind = "policy"` |
| `guard_` | (combinator) | `plat-flow:guard:{name} = {condition}` |

### Events (`Plat.Ext.Events`)

| Constructor | Base / Context | Meta tag |
|-------------|---------------|----------|
| `event` | `model` | `plat-events:kind = "event"` |
| `emit` | `DeclWriter 'Operation` | `plat-events:emit:{name} = {name}` |
| `on_` | `operation` | `plat-events:kind = "handler"` + `plat-events:on = {eventName}` |
| `apply_` | `DeclWriter 'Model` | `plat-events:apply:{name} = {name}` |

### Modules (`Plat.Ext.Modules`)

| Constructor | Base / Context | Meta tag |
|-------------|---------------|----------|
| `domain` | `compose` | `plat-modules:kind = "domain"` |
| `expose` | `DeclWriter 'Compose` | `plat-modules:expose:{name} = {name}` + entry |
| `import_` | `DeclWriter 'Compose` | `plat-modules:import:{targetName} = {srcName}` |
