# Internal Architecture

plat の内部構造と設計判断の詳細。

## Module Map

```
Plat.Core              -- 公開 API re-export (ユーザーはここだけ import すればよい)
Plat.Core.Types        -- AST: DeclKind, Declaration, Decl k, DeclItem, TypeExpr (TExt 含む),
                       --      ArchConstraint, Relation, Architecture
Plat.Core.Builder      -- DeclWriter k, ArchBuilder (State モナド)
                       --   constrain, relate
Plat.Core.TypeExpr     -- 型コンストラクタ: string, ref, ext (TExt), customType (TRef), (.:)
Plat.Core.Meta         -- 拡張メタ DSL: ExtId, MetaTag, tagAs, annotate, refer, attr
Plat.Core.Constraint   -- 制約述語: require, forbid, forAll, holds
                       --   合成: both, allOf, oneOf, neg
Plat.Core.Relation     -- 関係クエリ: relations, dependsOn, implementedBy, transitive, isAcyclic
Plat.Core.Algebra      -- 代数操作: merge (Either), mergeAll, isCompatible, project, diff

Plat.Check             -- check, checkWith, checkIO, prettyCheck
                       --   (archConstraints も自動評価)
Plat.Check.Class       -- PlatRule type class, SomeRule (GADT), Diagnostic
Plat.Check.Rules       -- V001-V009, W001-W004 の実装
Plat.Check.Presets     -- 制約プリセット: operationNeedsBoundary, unwiredBoundaries, noNeedsCycle

Plat.Generate.Mermaid  -- Mermaid flowchart 生成
Plat.Generate.Markdown -- Markdown ドキュメント生成

Plat.Ext.*             -- 拡張モジュール (DDD, CQRS, CleanArch, Http, DBC, Flow, Events, Modules)
                       --   各拡張が {ext}Rules :: [SomeRule] をエクスポート

Plat.Verify.Manifest   -- Architecture → JSON manifest
                       --   ManifestConstraint, ManifestRelation 含む
```

## AST Design

### DeclKind x DeclItem Matrix

各 DeclKind で使用可能な DeclItem:

|            | Field | Op | Input | Output | Needs | Implements | Inject | Bind | Entry |
|------------|:-----:|:--:|:-----:|:------:|:-----:|:----------:|:------:|:----:|:-----:|
| Model      |   o   |    |       |        |       |            |        |      |       |
| Boundary   |       | o  |       |        |       |            |        |      |       |
| Operation  |       |    |   o   |   o    |   o   |            |        |      |       |
| Adapter    |       |    |       |        |       |     o      |   o    |      |       |
| Compose    |       |    |       |        |       |            |        |  o   |   o   |

この制約は DeclWriter の phantom 型パラメータでコンパイル時に強制される。

### TypeExpr

```
TBuiltin Builtin           -- String, Int, Float, Decimal, Bool, Unit, Bytes, DateTime, Any
TRef Text                  -- 名前による参照 (model名, boundary名, customType)
TGeneric Text [TypeExpr]   -- List<T>, Map<K,V>, Option<T>, Result<T,E>, etc.
TNullable TypeExpr         -- T?
TExt Text                  -- 外部型 (ext で生成、W002 対象外)
```

`ext` は `TExt` を生成し、`ref`/`customType` は `TRef` を生成する。この AST レベルの区別により、W002 検証と `typeRefs` 関数で外部型を正確に除外できる。

### Meta

`meta :: Text -> Text -> DeclWriter k ()` は任意のキーバリューを宣言に付与する。
拡張モジュールはすべて meta ベースで実装される (DeclItem を追加しない)。

命名規約: `"plat-{extension}:{key}"` (例: `"plat-ddd:kind"`, `"plat-http:route:PlaceOrder"`)

## Monad Design

DeclWriter と ArchBuilder は **mtl に依存しない手動 State モナド**:

```haskell
newtype DeclWriter (k :: DeclKind) a = DeclWriter (DeclBuild -> (a, DeclBuild))
newtype ArchBuilder a = ArchBuilder (ArchBuild -> (a, ArchBuild))
```

Functor / Applicative / Monad を手動実装。外部依存は base, text, containers, directory のみ。

### Architecture Fields

```
Architecture
  archName        :: Text              -- アーキテクチャ名
  archLayers      :: [LayerDef]        -- レイヤー定義
  archTypes       :: [TypeAlias]       -- 型エイリアス
  archCustomTypes :: [Text]            -- registerType 登録型
  archDecls       :: [Declaration]     -- 全宣言
  archConstraints :: [ArchConstraint]  -- 制約 (constrain で登録)
  archRelations   :: [Relation]        -- 明示的関係 (relate で登録)
  archMeta        :: [(Text, Text)]    -- メタデータ
```

`archConstraints` は `check` で自動評価される。違反は `C:{name}` コードの Error として報告。

`archRelations` は `relate` で登録した明示的関係のみ。`relations :: Architecture -> [Relation]` で
DeclItem 由来の暗黙的関係 (needs, implements, bind, entry, references) と統合される。

### Architecture Algebra

`Plat.Core.Algebra` が提供する代数操作:

- `merge name a b` — 2つの Architecture を合成。互換性チェック付き (`Either [Conflict] Architecture`)
- `mergeAll name as` — 複数を合成
- `isCompatible a b` — 互換性チェック (コンフリクトのリスト)
- `project pred a` — 述語で Declaration をフィルタ (孤立 Relation も除去)
- `projectLayer layer a` — レイヤーで射影
- `projectKind kind a` — 宣言種で射影
- `diff old new` — 構造差分 (ArchDiff: Added/Removed/Modified)

## Check Engine

```
PlatRule (type class)
  ├── ruleCode :: Text
  ├── checkDecl :: Architecture -> Declaration -> [Diagnostic]
  └── checkArch :: Architecture -> [Diagnostic]

SomeRule (existential GADT)
  └── SomeRule :: PlatRule a => a -> SomeRule
```

`checkWith :: [SomeRule] -> Architecture -> CheckResult` が全ルールを走査し、
さらに `archConstraints` を評価して結果を合成する。
CheckResult は Monoid なので `<>` で合成可能。

## Generator Design

各 Generator は `Architecture -> Text` のシンプルな関数。
