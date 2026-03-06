-- | Modules 拡張: domain, expose, import_
module Plat.Ext.Modules
  ( domain
  , expose
  , import_
  , modulesRules
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Check.Class

-- | ドメインモジュール（compose として表現: 宣言のグルーピング）
domain :: Text -> DeclWriter 'Compose () -> Decl 'Compose
domain name body = compose name $ do
  meta "plat-modules:kind" "domain"
  body

-- | モジュールから宣言を公開
expose :: Decl k -> DeclWriter 'Compose ()
expose d = do
  let name = declName (unDecl d)
  meta ("plat-modules:expose:" <> name) name
  entry d

-- | 別モジュールの宣言を参照（メタデータとして記録）
import_ :: Decl 'Compose -> Decl k -> DeclWriter 'Compose ()
import_ src target =
  meta ("plat-modules:import:" <> declName (unDecl target)) (declName (unDecl src))

modulesRules :: [SomeRule]
modulesRules = []
