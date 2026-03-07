# Internal Architecture

plat の内部構造と設計判断の詳細。

## Module Map

```
Plat.Core              -- 公開 API re-export (ユーザーはここだけ import すればよい)
Plat.Core.Types        -- AST: DeclKind, Declaration, Decl k, DeclItem, TypeExpr
Plat.Core.Builder      -- DeclWriter k, ArchBuilder (State モナド)
Plat.Core.TypeExpr     -- 型コンストラクタ: string, ref, ext, (.:)
Plat.Core.Meta         -- 拡張メタ DSL: ExtId, MetaTag, tagAs, annotate, refer, attr

Plat.Check             -- check, checkWith, checkIO, prettyCheck
Plat.Check.Class       -- PlatRule type class, SomeRule (GADT), Diagnostic
Plat.Check.Rules       -- V001-V008, W001-W003 の実装

Plat.Generate.Plat     -- .plat テキスト生成
Plat.Generate.Mermaid  -- Mermaid flowchart 生成
Plat.Generate.Markdown -- Markdown ドキュメント生成

Plat.Ext.*             -- 拡張モジュール (DDD, CQRS, CleanArch, Http, DBC, Flow, Events, Modules)

Plat.Target.Go         -- Go コード生成 (skeleton, contract, verify)
Plat.Target.TypeScript -- TypeScript コード生成
Plat.Target.Rust       -- Rust コード生成

Plat.Verify.Manifest   -- Architecture → JSON manifest
Plat.Verify.DepRules   -- レイヤー依存 → linter 設定生成
```

## AST Design

### DeclKind × DeclItem Matrix

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
TRef Text                  -- 名前による参照 (model名, boundary名, ext, customType)
TGeneric Text [TypeExpr]   -- List<T>, Map<K,V>, Option<T>, Result<T,E>, etc.
TNullable TypeExpr         -- T?
```

`ext` と `customType` はどちらも `TRef` を生成するが、意味が異なる:
- `ext`: ターゲット言語の型。W002 検証対象外 (Inject 内の TRef は検査しない)
- `customType`: プロジェクト定義の型。`registerType` で登録しないと W002 警告

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

## Check Engine

```
PlatRule (type class)
  ├── ruleCode :: Text
  ├── checkDecl :: Architecture -> Declaration -> [Diagnostic]
  └── checkArch :: Architecture -> [Diagnostic]

SomeRule (existential GADT)
  └── SomeRule :: PlatRule a => a -> SomeRule
```

`checkWith :: [SomeRule] -> Architecture -> CheckResult` が全ルールを走査。
CheckResult は Monoid なので `<>` で合成可能。

## Generator Design

各 Generator は `Architecture -> Text` のシンプルな関数。
`renderFiles` のみ `Architecture -> [(FilePath, Text)]` でファイル分割を行う。
