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

#### V009: Duplicate Declaration Name

同一アーキテクチャ内に同名の宣言が複数存在する場合。`archDecls` で `checkArch` 時に検出。

#### V010: Relation Reference Validity

`relate` で登録された明示的関係の `relSource` または `relTarget` が `archDecls` 内に存在しない場合。severity は Warning（明示的関係はサービス名など非宣言を参照する場合がある）。

### Warnings (W-codes)

#### W001: Unresolved Boundary

boundary に対応する adapter (implements) が architecture 内に存在しない場合。

#### W002: Undefined Type Reference

`TRef` で参照された型名が、architecture 内の宣言名・TypeAlias 名・`registerType` 済み型名・予約型名 (`Error`, `Id`) のいずれにも該当しない場合。

**免除**: `TExt` (ext で生成) は検査対象外。`Inject` 内の `TRef` も検査しない。

#### W003: Multiple Implements

adapter に複数の `implements` が存在する場合。最後の値のみが有効 (last-write-wins) であることを警告する。

#### W004: Path File Not Found

`@path` で指定されたファイルが存在しない場合。`checkIO` でのみ検査 (IO が必要)。`check` (純粋) では検査されない。

## Extension Rules

| Module | Code | Severity | Description |
|--------|------|----------|-------------|
| `Plat.Ext.DDD` | DDD-V001 | Error | value object に Id フィールドがある |
| `Plat.Ext.DDD` | DDD-V002 | Warning | aggregate に Id フィールドがない |
| `Plat.Ext.DBC` | DBC-W001 | Warning | pre/post を持つ operation に needs がない |
| `Plat.Ext.CleanArch` | CA-V001 | Error | caImpl タグ付き adapter に implements がない |
| `Plat.Ext.CleanArch` | CA-W001 | Warning | caWire タグ付き compose に bind がない |
| `Plat.Ext.Http` | HTTP-W001 | Warning | controller に route がない |
| `Plat.Ext.Events` | EVT-V001 | Error | emit されたイベントが architecture に存在しない |
| `Plat.Ext.Events` | EVT-W001 | Warning | handler の対象イベントが architecture に存在しない |
| `Plat.Ext.Modules` | MOD-V001 | Error | expose された宣言が architecture に存在しない |
| `Plat.Ext.Modules` | MOD-V002 | Error | import 元のモジュールが architecture に存在しない |

```haskell
checkWith (coreRules ++ dddRules ++ dbcRules ++ cleanArchRules
          ++ httpRules ++ eventsRules ++ modulesRules) architecture
```
