# 拡張システム

拡張は core の AST (`DeclItem`) を変更しない。smart constructor + `meta` タグの薄いラッパーとして実装される。

## Meta DSL (`Plat.Core.Meta`)

拡張メタデータは4つの構造パターンに分類される。内部表現はすべて `[(Text, Text)]`。

| Pattern | Write | Query | Key format |
|---------|-------|-------|------------|
| Kind tag | `tagAs tag` | `isTagged tag d` | `plat-{ext}:kind` |
| Attribute | `attr ext key val` | `lookupAttr ext key d` | `plat-{ext}:{key}` |
| Annotation | `annotate ext cat name val` | `annotations ext cat d` | `plat-{ext}:{cat}:{name}` |
| Reference | `refer ext cat decl` | `references ext cat d` | `plat-{ext}:{cat}:{declName}` |

```haskell
-- 識別子と分類タグ
type ExtId   -- 拡張の名前空間
type MetaTag -- kind の値

extId :: Text -> ExtId
kind  :: ExtId -> Text -> MetaTag
```

## 拡張の実装パターン

```haskell
-- 1. Meta vocabulary
ddd :: ExtId
ddd = extId "ddd"

dddAggregate :: MetaTag
dddAggregate = kind ddd "aggregate"

-- 2. Smart constructor
aggregate :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
aggregate name ly body = model name ly $ do
  tagAs dddAggregate
  body

-- 3. Query helper
isAggregate :: Declaration -> Bool
isAggregate d = declKind d == Model && isTagged dddAggregate d

-- 4. Optional rule
data AggregateIdRule = AggregateIdRule
instance PlatRule AggregateIdRule where ...

dddRules :: [SomeRule]
dddRules = [SomeRule ValueNoIdRule, SomeRule AggregateIdRule]
```

## 標準拡張モジュール

### DDD (`Plat.Ext.DDD`)

ExtId: `ddd` / Tags: `dddValue`, `dddAggregate`, `dddEnum`

| Constructor | Base | Meta pattern |
|-------------|------|--------------|
| `value` | `model` | `tagAs dddValue` |
| `aggregate` | `model` | `tagAs dddAggregate` |
| `enum` | `model` | `tagAs dddEnum` + `annotate ddd "variant"` |
| `invariant` | (combinator) | `annotate ddd "invariant" name expr` |

Rules: DDD-V001 (value with id), DDD-V002 (aggregate without id)

### CQRS (`Plat.Ext.CQRS`)

ExtId: `cqrs` / Tags: `cqrsCommand`, `cqrsQuery`

| Constructor | Base | Meta pattern |
|-------------|------|--------------|
| `command` | `operation` | `tagAs cqrsCommand` |
| `query` | `operation` | `tagAs cqrsQuery` |

Helpers: `isCommand`, `isQuery`

### CleanArch (`Plat.Ext.CleanArch`)

ExtId: `cleanArch` / Tags: `caEntity`, `caUsecase`, `caPort`, `caImpl`, `caWire`

Preset layers: `enterprise`, `application`, `interface`, `framework` (+ `cleanArchLayers`)

| Constructor | Base | Meta pattern |
|-------------|------|--------------|
| `entity` | `model` | `tagAs caEntity` |
| `usecase` | `operation` | `tagAs caUsecase` |
| `port` | `boundary` | `tagAs caPort` |
| `impl` | `adapter` + `implements` | `tagAs caImpl` |
| `wire` | `compose` | `tagAs caWire` |

Rules: CA-V001 (impl without implements), CA-W001 (wire without bindings)

### Http (`Plat.Ext.Http`)

ExtId: `http` / Tags: `httpController`

| Constructor | Base | Meta pattern |
|-------------|------|--------------|
| `controller` | `adapter` | `tagAs httpController` |
| `route` | (combinator) | `annotate http "route" opName val` + inject |

`route` は meta にルート情報を記録しつつ、target operation を inject する。

Rules: HTTP-W001 (controller without routes)

### DBC (`Plat.Ext.DBC`)

ExtId: `dbc`

| Constructor | Context | Meta pattern |
|-------------|---------|--------------|
| `pre` | `DeclWriter 'Operation` | `annotate dbc "pre" name expr` |
| `post` | `DeclWriter 'Operation` | `annotate dbc "post" name expr` |
| `assert_` | `DeclWriter k` (universal) | `annotate dbc "assert" name expr` |

Rules: DBC-W001 (contracts without needs)

### Flow (`Plat.Ext.Flow`)

ExtId: `flow` / Tags: `flowStep`, `flowPolicy`, `flowProjection`

| Constructor | Base | Meta pattern |
|-------------|------|--------------|
| `step` | `operation` | `tagAs flowStep` |
| `policy` | `model` | `tagAs flowPolicy` |
| `guard_` | (combinator) | `annotate flow "guard" name condition` |

### Events (`Plat.Ext.Events`)

ExtId: `events` / Tags: `evtEvent`, `evtHandler`

| Constructor | Base / Context | Meta pattern |
|-------------|---------------|--------------|
| `event` | `model` | `tagAs evtEvent` |
| `emit` | `DeclWriter 'Operation` | `refer events "emit" decl` |
| `on_` | `operation` | `tagAs evtHandler` + `attr events "on" eventName` |
| `apply` | `DeclWriter 'Model` | `refer events "apply" decl` |

Rules: EVT-V001 (emit unknown event), EVT-W001 (handler targets unknown event)

### Modules (`Plat.Ext.Modules`)

ExtId: `modules` / Tags: `modulesDomain`

| Constructor | Base / Context | Meta pattern |
|-------------|---------------|--------------|
| `domain` | `compose` | `tagAs modulesDomain` |
| `expose` | `DeclWriter 'Compose` | `refer modules "expose" decl` + entry |
| `import_` | `DeclWriter 'Compose` | `annotate modules "import" targetName srcName` |

Rules: MOD-V001 (expose unknown decl), MOD-V002 (import unknown module)
