-- | Rust code generation: skeleton, contract tests, compile-time verification.
module Plat.Target.Rust
  ( RsConfig (..)
  , defaultConfig
  , skeleton
  , contract
  , verify
  ) where

import Data.Char (toLower, isUpper)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe)
import qualified Data.Map.Strict as Map

import Plat.Core.Types

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------

data RsConfig = RsConfig
  { rsTypeMap  :: Map.Map Text Text   -- ^ Custom type overrides
  , rsLayerMod :: Map.Map Text Text   -- ^ Layer → module name overrides
  }

defaultConfig :: RsConfig
defaultConfig = RsConfig
  { rsTypeMap  = Map.fromList [("Error", "String")]
  , rsLayerMod = Map.empty
  }

----------------------------------------------------------------------
-- Type mapping
----------------------------------------------------------------------

layerMod :: RsConfig -> Text -> Text
layerMod cfg ly = Map.findWithDefault ly ly (rsLayerMod cfg)

rsType :: RsConfig -> TypeExpr -> Text
rsType _   (TBuiltin BString)   = "String"
rsType _   (TBuiltin BInt)      = "i64"
rsType _   (TBuiltin BFloat)    = "f64"
rsType _   (TBuiltin BDecimal)  = "f64"
rsType _   (TBuiltin BBool)     = "bool"
rsType _   (TBuiltin BUnit)     = "()"
rsType _   (TBuiltin BBytes)    = "Vec<u8>"
rsType _   (TBuiltin BDateTime) = "String"
rsType _   (TBuiltin BAny)      = "Box<dyn std::any::Any>"
rsType cfg (TRef name)          = Map.findWithDefault name name (rsTypeMap cfg)
rsType cfg (TGeneric "List" [t])     = "Vec<" <> rsType cfg t <> ">"
rsType cfg (TGeneric "Set" [t])      = "HashSet<" <> rsType cfg t <> ">"
rsType cfg (TGeneric "Map" [k, v])   = "HashMap<" <> rsType cfg k <> ", " <> rsType cfg v <> ">"
rsType cfg (TGeneric "Option" [t])   = "Option<" <> rsType cfg t <> ">"
rsType cfg (TGeneric "Result" [t, e]) = "Result<" <> rsType cfg t <> ", " <> rsType cfg e <> ">"
rsType cfg (TGeneric "Stream" [t])   = "impl Stream<Item = " <> rsType cfg t <> ">"
rsType cfg (TGeneric "Id" [t])       = rsType cfg t <> "Id"
rsType cfg (TGeneric n ts)          = n <> "<" <> T.intercalate ", " (map (rsType cfg) ts) <> ">"
rsType cfg (TNullable t)             = "Option<" <> rsType cfg t <> ">"

----------------------------------------------------------------------
-- Name conventions
----------------------------------------------------------------------

toSnake :: Text -> Text
toSnake = T.pack . go . T.unpack
  where
    go [] = []
    go (c:cs)
      | isUpper c = '_' : toLower c : go cs
      | otherwise = c : go cs

snakeName :: Text -> Text
snakeName t = case T.uncons (toSnake t) of
  Just ('_', rest) -> rest
  _                -> toSnake t

----------------------------------------------------------------------
-- Skeleton generation
----------------------------------------------------------------------

skeleton :: RsConfig -> Architecture -> [(FilePath, Text)]
skeleton cfg arch =
  let decls = archDecls arch
      byLayer = groupByLayer decls
      modFiles = concatMap (skelLayer cfg arch) byLayer
      -- mod.rs for each layer
      modRs = map (layerModRs cfg) byLayer
  in modFiles ++ modRs

groupByLayer :: [Declaration] -> [(Maybe Text, [Declaration])]
groupByLayer ds = Map.toList $ Map.fromListWith (++)
  [(declLayer d, [d]) | d <- ds, declKind d /= Compose]

layerModRs :: RsConfig -> (Maybe Text, [Declaration]) -> (FilePath, Text)
layerModRs cfg (mbLy, ds) =
  let dir = maybe "lib" (layerMod cfg) mbLy
      mods = map (\d -> "pub mod " <> snakeName (declName d) <> ";") ds
  in (T.unpack dir <> "/mod.rs", T.unlines mods)

skelLayer :: RsConfig -> Architecture -> (Maybe Text, [Declaration]) -> [(FilePath, Text)]
skelLayer cfg arch (_, ds) = concatMap (skelDecl cfg arch) ds

skelDecl :: RsConfig -> Architecture -> Declaration -> [(FilePath, Text)]
skelDecl cfg arch d = case declKind d of
  Model     -> skelModel cfg d
  Boundary  -> skelBoundary cfg d
  Operation -> skelOperation cfg arch d
  Adapter   -> skelAdapter cfg arch d
  Compose   -> []

skelModel :: RsConfig -> Declaration -> [(FilePath, Text)]
skelModel cfg d =
  let dir = maybe "domain" (layerMod cfg) (declLayer d)
      name = declName d
      fields = declFields d
      body = T.unlines $
        [ "// Generated from model " <> name
        , ""
        , "#[derive(Debug, Clone)]"
        , "pub struct " <> name <> " {"
        ] ++
        [ "    pub " <> snakeName fn <> ": " <> rsType cfg ft <> ","
        | (fn, ft) <- fields
        ] ++
        [ "}"
        ]
      fp = T.unpack dir <> "/" <> T.unpack (snakeName name) <> ".rs"
  in [(fp, body)]

skelBoundary :: RsConfig -> Declaration -> [(FilePath, Text)]
skelBoundary cfg d =
  let dir = maybe "domain" (layerMod cfg) (declLayer d)
      name = declName d
      ops = declOps d
      body = T.unlines $
        [ "// Generated from boundary " <> name
        , ""
        , "pub trait " <> name <> " {"
        ] ++
        map (renderTraitMethod cfg) ops ++
        [ "}"
        ]
      fp = T.unpack dir <> "/" <> T.unpack (snakeName name) <> ".rs"
  in [(fp, body)]

renderTraitMethod :: RsConfig -> (Text, [Param], [Param]) -> Text
renderTraitMethod cfg (name, ins, outs) =
  let params = T.intercalate ", " $
        ["&mut self"] ++
        [snakeName pn <> ": " <> rsType cfg pt | Param pn pt <- ins]
      retType = rsReturnType cfg outs
  in "    fn " <> snakeName name <> "(" <> params <> ") -> " <> retType <> ";"

rsReturnType :: RsConfig -> [Param] -> Text
rsReturnType _ [] = "()"
rsReturnType cfg outs =
  let hasError = any (\(Param _ pt) -> isErrorType pt) outs
      nonErr   = filter (\(Param _ pt) -> not (isErrorType pt)) outs
  in case (nonErr, hasError) of
    ([], True)        -> "Result<(), String>"
    ([Param _ t], True)  -> "Result<" <> rsType cfg t <> ", String>"
    (ps, True)        -> "Result<(" <> T.intercalate ", " (map (\(Param _ t) -> rsType cfg t) ps) <> "), String>"
    ([Param _ t], False) -> rsType cfg t
    (ps, False)       -> "(" <> T.intercalate ", " (map (\(Param _ t) -> rsType cfg t) ps) <> ")"

isErrorType :: TypeExpr -> Bool
isErrorType (TRef "Error") = True
isErrorType _              = False

skelOperation :: RsConfig -> Architecture -> Declaration -> [(FilePath, Text)]
skelOperation cfg arch d =
  let dir = maybe "application" (layerMod cfg) (declLayer d)
      name = declName d
      ins  = [(pn, pt) | Input pn pt <- declBody d]
      outs = [Param pn pt | Output pn pt <- declBody d]
      deps = declNeeds d
      depDecls = mapMaybe (\n -> lookupDecl n arch) deps
      retType = rsReturnType cfg outs
      body = T.unlines $
        [ "// Generated from operation " <> name
        , ""
        , "pub fn execute("
        ] ++
        [ "    " <> snakeName (declName dd) <> ": &mut impl " <> declName dd <> ","
        | dd <- depDecls
        ] ++
        [ "    " <> snakeName n <> ": " <> rsType cfg t <> ","
        | (n, t) <- ins
        ] ++
        [ ") -> " <> retType <> " {"
        , "    todo!(\"implement " <> name <> "\")"
        , "}"
        ]
      fp = T.unpack dir <> "/" <> T.unpack (snakeName name) <> ".rs"
  in [(fp, body)]

skelAdapter :: RsConfig -> Architecture -> Declaration -> [(FilePath, Text)]
skelAdapter cfg arch d =
  let dir = maybe "infrastructure" (layerMod cfg) (declLayer d)
      name = declName d
      injects = [(n, t) | Inject n t <- declBody d]
      mbImpl = findImplements (declBody d) >>= \bn -> lookupDecl bn arch
      body = T.unlines $
        [ "// Generated from adapter " <> name
        , ""
        , "pub struct " <> name <> " {"
        ] ++
        [ "    pub " <> snakeName n <> ": " <> rsType cfg t <> ","
        | (n, t) <- injects
        ] ++
        [ "}"
        ] ++
        -- Generate trait impl stub
        (case mbImpl of
          Nothing -> []
          Just impl ->
            [ ""
            , "impl " <> declName impl <> " for " <> name <> " {"
            ] ++
            concatMap (implMethodStub cfg) (declOps impl) ++
            [ "}"
            ])
      fp = T.unpack dir <> "/" <> T.unpack (snakeName name) <> ".rs"
  in [(fp, body)]

implMethodStub :: RsConfig -> (Text, [Param], [Param]) -> [Text]
implMethodStub cfg (name, ins, outs) =
  let params = T.intercalate ", " $
        ["&mut self"] ++
        [snakeName pn <> ": " <> rsType cfg pt | Param pn pt <- ins]
      retType = rsReturnType cfg outs
  in [ "    fn " <> snakeName name <> "(" <> params <> ") -> " <> retType <> " {"
     , "        todo!(\"implement " <> name <> "\")"
     , "    }"
     ]

----------------------------------------------------------------------
-- Contract tests
----------------------------------------------------------------------

contract :: RsConfig -> Architecture -> [(FilePath, Text)]
contract cfg arch =
  let boundaries = [d | d <- archDecls arch, declKind d == Boundary]
  in map (contractBoundary cfg) boundaries

contractBoundary :: RsConfig -> Declaration -> (FilePath, Text)
contractBoundary cfg bnd =
  let dir = maybe "domain" (layerMod cfg) (declLayer bnd)
      name = declName bnd
      ops = declOps bnd
      body = T.unlines $
        [ "// Contract tests for " <> name
        , "// Any type implementing " <> name <> " must pass these tests."
        , ""
        , "#[cfg(test)]"
        , "pub fn test_" <> snakeName name <> "_contract(adapter: &mut impl " <> name <> ") {"
        ] ++
        concatMap (contractOp cfg) ops ++
        [ "}"
        ]
      fp = T.unpack dir <> "/" <> T.unpack (snakeName name) <> "_contract.rs"
  in (fp, body)

contractOp :: RsConfig -> (Text, [Param], [Param]) -> [Text]
contractOp cfg (name, ins, outs) =
  let args = T.intercalate ", " [zeroValue cfg pt | Param _ pt <- ins]
      hasError = any (\(Param _ pt) -> isErrorType pt) outs
      call = "adapter." <> snakeName name <> "(" <> args <> ")"
  in [ "    // Test: " <> name
     , if hasError
       then "    let _ = " <> call <> ";"
       else "    let _ = " <> call <> ";"
     ]

zeroValue :: RsConfig -> TypeExpr -> Text
zeroValue _   (TBuiltin BString)   = "String::new()"
zeroValue _   (TBuiltin BInt)      = "0"
zeroValue _   (TBuiltin BFloat)    = "0.0"
zeroValue _   (TBuiltin BDecimal)  = "0.0"
zeroValue _   (TBuiltin BBool)     = "false"
zeroValue _   (TBuiltin BUnit)     = "()"
zeroValue _   (TBuiltin BBytes)    = "vec![]"
zeroValue _   (TBuiltin BDateTime) = "String::new()"
zeroValue _   (TBuiltin BAny)      = "Box::new(())"
zeroValue _   (TRef _)             = "Default::default()"
zeroValue _   (TGeneric "List" _)  = "vec![]"
zeroValue _   (TNullable _)        = "None"
zeroValue _   _                    = "Default::default()"

----------------------------------------------------------------------
-- Compile-time verification
----------------------------------------------------------------------

verify :: RsConfig -> Architecture -> [(FilePath, Text)]
verify cfg arch =
  let adapters = [(d, bnd) | d <- archDecls arch, declKind d == Adapter,
                  Just bndName <- [findImplements (declBody d)],
                  Just bnd <- [lookupDecl bndName arch]]
  in if null adapters then []
     else
       let body = T.unlines $
             [ "// Generated by plat-hs — compile-time architecture conformance."
             , "// If this file fails to compile, the implementation does not"
             , "// match the architecture."
             , ""
             ] ++
             concatMap (verifyPair cfg) adapters ++
             [ ""
             , "#[allow(dead_code)]"
             , "fn _verify_architecture() {"
             ] ++
             [ "    _assert_" <> snakeName (declName adp) <> "();"
             | (adp, _) <- adapters
             ] ++
             [ "}"
             ]
       in [("verify/verify_architecture.rs", body)]

verifyPair :: RsConfig -> (Declaration, Declaration) -> [Text]
verifyPair _cfg (adp, bnd) =
  [ "#[allow(dead_code)]"
  , "fn _assert_" <> snakeName (declName adp) <> "() {"
  , "    fn _check<T: " <> declName bnd <> ">() {}"
  , "    _check::<" <> declName adp <> ">();"
  , "}"
  , ""
  ]

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

lookupDecl :: Text -> Architecture -> Maybe Declaration
lookupDecl name arch = case [d | d <- archDecls arch, declName d == name] of
  (d:_) -> Just d
  []    -> Nothing
