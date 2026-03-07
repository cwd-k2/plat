# 検証システム

`check` / `checkWith` による検証ルールの適用。PlatRule 型クラスによる拡張可能な設計。

## API

```haskell
check       :: Architecture -> CheckResult
checkIO     :: Architecture -> IO CheckResult      -- W004 (IO) を含む
checkWith   :: [SomeRule] -> Architecture -> CheckResult
prettyCheck :: CheckResult -> Text
checkOrFail :: Architecture -> IO ()

hasViolations :: CheckResult -> Bool
hasWarnings   :: CheckResult -> Bool
```

`check` は純粋な検証 (V001-V009, W001-W003) を実行する。`checkIO` は `check` の結果に加えて W004 (ファイル存在確認) を IO で実行する。`checkWith` は `archConstraints` に登録された制約も自動評価する。

## CheckResult / Diagnostic

```haskell
data CheckResult = CheckResult
  { violations :: [Diagnostic]
  , warnings   :: [Diagnostic]
  }

instance Semigroup CheckResult   -- 合成可能
instance Monoid CheckResult

data Diagnostic = Diagnostic
  { dSeverity :: Severity
  , dCode     :: Text
  , dMessage  :: Text
  , dSource   :: Text
  , dTarget   :: Maybe Text
  }

data Severity = Error | Warning
```

## PlatRule 型クラス

```haskell
class PlatRule a where
  ruleCode  :: a -> Text
  checkDecl :: a -> Architecture -> Declaration -> [Diagnostic]
  checkDecl _ _ _ = []
  checkArch :: a -> Architecture -> [Diagnostic]
  checkArch _ _ = []

data SomeRule where
  SomeRule :: PlatRule a => a -> SomeRule

coreRules :: [SomeRule]
```

## Core ルール一覧

### Errors (V-codes)

| Code | Rule | 検証内容 |
|------|------|---------|
| V001 | `LayerDepRule` | レイヤー依存違反 — 宣言のレイヤーが依存先のレイヤーに依存を許可しているか |
| V002 | `LayerCycleRule` | レイヤー循環依存 (`checkArch`) |
| V003 | `NeedsKindRule` | `needs` の対象が boundary であるか |
| V004 | `BoundaryKindRule` | boundary に adapter 固有の要素 (Inject, Implements) がないか |
| V005 | `BindScopeRule` | `bind` が compose 内にのみ存在するか |
| V006 | `KeywordCollisionRule` | 宣言名が予約語と衝突しないか (`checkArch`) |
| V007 | `AdapterCoverageRule` | adapter が implements した boundary の全 op を持つか |
| V008 | `BindTargetRule` | `bind` の左辺が boundary、右辺が adapter であるか |
| V009 | `DuplicateNameRule` | 同名の宣言が複数存在しないか (`checkArch`) |

**V003, V005, V008**: phantom type の導入により eDSL 経由の構築では到達不能。ランタイムルールとしても残す。

**V007 の条件付き適用**: `Implements` を含む adapter にのみ適用。adapter に Op がなければ暗黙的全カバーとみなす。

### Warnings (W-codes)

| Code | Rule | 検証内容 |
|------|------|---------|
| W001 | `UnresolvedBoundaryRule` | boundary に対応する adapter (implements) が存在しない |
| W002 | `UndefinedTypeRule` | `TRef` が宣言名・TypeAlias・customType・予約型で解決できない。`TExt` は検査対象外。`Inject` 内の `TRef` も除外 |
| W003 | `MultipleImplementsRule` | adapter に複数の `implements` がある (最後の値のみ有効) |
| W004 | `PathExistsRule` | `@path` のファイルが存在しない (`checkIO` 専用) |

## Extension ルール一覧

| Module | Code | Severity | 検証内容 |
|--------|------|----------|---------|
| `Plat.Ext.DDD` | DDD-V001 | Error | value object に Id フィールドがある |
| `Plat.Ext.DDD` | DDD-V002 | Warning | aggregate に Id フィールドがない |
| `Plat.Ext.DBC` | DBC-W001 | Warning | pre/post を持つ operation に needs がない |
| `Plat.Ext.CleanArch` | CA-V001 | Error | `caImpl` タグ付き adapter に implements がない |
| `Plat.Ext.CleanArch` | CA-W001 | Warning | `caWire` タグ付き compose に bind がない |
| `Plat.Ext.Http` | HTTP-W001 | Warning | controller に route がない |
| `Plat.Ext.Events` | EVT-V001 | Error | emit されたイベントが architecture に存在しない |
| `Plat.Ext.Events` | EVT-W001 | Warning | handler の対象イベントが architecture に存在しない |
| `Plat.Ext.Modules` | MOD-V001 | Error | expose された宣言が architecture に存在しない |
| `Plat.Ext.Modules` | MOD-V002 | Error | import 元のモジュールが architecture に存在しない |

```haskell
checkWith (coreRules ++ dddRules ++ dbcRules ++ cleanArchRules) architecture
```

## ルール追加手順

1. `src-hs/Plat/Check/Rules.hs` (core) または `src-hs/Plat/Ext/*.hs` (拡張) に data 型を定義
2. `PlatRule` instance を実装
3. ルールリストに追加 (`coreRules` または `{ext}Rules`)
4. テスト追加
