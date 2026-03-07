# Validation Rules

## Core Rules

`check` / `checkWith coreRules` で適用されるルール。

### Errors (V-codes)

#### V001: Layer Dependency Violation

operation が `needs` で参照する boundary、adapter が `implements` する boundary、compose の `bind` 対象について、宣言のレイヤーからターゲットのレイヤーへの依存が `useLayers` で許可されていなければエラー。

同一レイヤー内の参照は常に許可。

#### V002: Layer Cycle

レイヤー依存グラフに循環がある場合。トポロジカルソートで検出。

#### V003: Needs Target Not Boundary

`needs` の引数はコンパイル時に `Decl 'Boundary` に制約されるが、`Declaration` レベルでの整合性もランタイムで検証する。

#### V004: Boundary Contains Adapter Items

boundary に `Inject` や `Implements` が含まれている場合。

#### V005: Bind Outside Compose

`Bind` が compose 以外の宣言に含まれている場合。

#### V006: Reserved Keyword Collision

宣言名が plat の予約語 (`model`, `boundary`, `operation`, `adapter`, `compose`, `layer`, `type`, `needs`, `implements`, `inject`, `bind`, `entry`) と衝突する場合。大文字小文字を区別しない。

#### V007: Adapter Coverage

adapter が `implements` した boundary の op をすべてカバーしているか。

**注意**: plat の adapter は boundary の op を再宣言しない (inject のみ持つ) ため、adapter に Op が一つもなければ「暗黙的全カバー」として扱う。Op を明示的に書いた場合のみ、boundary の op との差分を検査する。

#### V008: Bind Type Mismatch

`bind` の左辺が boundary でない、または右辺が adapter でない場合。

### Warnings (W-codes)

#### W001: Unresolved Boundary

boundary に対応する adapter (implements) が architecture 内に存在しない場合。

#### W002: Undefined Type Reference

`TRef` で参照された型名が、architecture 内の宣言名・TypeAlias 名・`registerType` 済み型名・予約型名 (`Error`, `Id`) のいずれにも該当しない場合。

**免除**: `Inject` 内の `TRef` は検査しない (`ext` で指定される外部型のため)。

#### W003: Path File Not Found

`@path` で指定されたファイルが存在しない場合。`checkIO` でのみ検査 (IO が必要)。

## Extension Rules

| Module | Code | Description |
|--------|------|-------------|
| `Plat.Ext.DDD` | DDD-V001 | value object に Id フィールドがある |
| `Plat.Ext.DDD` | DDD-V002 | aggregate に Id フィールドがない (warning) |
| `Plat.Ext.DBC` | DBC-W001 | pre/post を持つ operation に needs がない (warning) |

```haskell
checkWith (coreRules ++ dddRules ++ dbcRules) architecture
```
