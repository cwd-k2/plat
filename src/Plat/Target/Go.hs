-- | Go code generation: skeleton, contract tests, compile-time verification.
module Plat.Target.Go
  ( GoConfig (..)
  , defaultConfig
  , skeleton
  , contract
  , verify
  ) where

import Data.Char (toLower, toUpper, isUpper)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe)
import qualified Data.Map.Strict as Map

import Plat.Core.Types

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------

data GoConfig = GoConfig
  { goModule   :: Text               -- ^ Go module path (e.g. "github.com/example/svc")
  , goTypeMap  :: Map.Map Text Text   -- ^ Custom type overrides: "UUID" -> "string"
  , goLayerPkg :: Map.Map Text Text   -- ^ Layer → package name overrides
  }

defaultConfig :: Text -> GoConfig
defaultConfig modPath = GoConfig
  { goModule   = modPath
  , goTypeMap  = Map.fromList [("Error", "error")]
  , goLayerPkg = Map.empty
  }

----------------------------------------------------------------------
-- Type mapping
----------------------------------------------------------------------

layerPkg :: GoConfig -> Text -> Text
layerPkg cfg ly = Map.findWithDefault ly ly (goLayerPkg cfg)

goType :: GoConfig -> TypeExpr -> Text
goType _   (TBuiltin BString)   = "string"
goType _   (TBuiltin BInt)      = "int"
goType _   (TBuiltin BFloat)    = "float64"
goType _   (TBuiltin BDecimal)  = "float64"
goType _   (TBuiltin BBool)     = "bool"
goType _   (TBuiltin BUnit)     = "struct{}"
goType _   (TBuiltin BBytes)    = "[]byte"
goType _   (TBuiltin BDateTime) = "time.Time"
goType _   (TBuiltin BAny)      = "any"
goType cfg (TRef name)          = Map.findWithDefault name name (goTypeMap cfg)
goType cfg (TGeneric "List" [t])     = "[]" <> goType cfg t
goType cfg (TGeneric "Set" [t])      = "map[" <> goType cfg t <> "]struct{}"
goType cfg (TGeneric "Map" [k, v])   = "map[" <> goType cfg k <> "]" <> goType cfg v
goType cfg (TGeneric "Option" [t])   = "*" <> goType cfg t
goType cfg (TGeneric "Stream" [t])   = "<-chan " <> goType cfg t
goType cfg (TGeneric "Id" [t])       = goType cfg t <> "ID"
goType cfg (TGeneric _ ts)           = T.intercalate ", " (map (goType cfg) ts)
goType cfg (TNullable t)             = "*" <> goType cfg t

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

-- | File name from declaration name: "OrderRepository" -> "order_repository"
fileName :: Text -> Text
fileName t = case T.uncons (toSnake t) of
  Just ('_', rest) -> rest  -- strip leading underscore
  _                -> toSnake t

exportedName :: Text -> Text
exportedName t = case T.uncons t of
  Just (c, rest) -> T.cons (toUpper c) rest
  Nothing        -> t

----------------------------------------------------------------------
-- Skeleton generation
----------------------------------------------------------------------

skeleton :: GoConfig -> Architecture -> [(FilePath, Text)]
skeleton cfg arch = concatMap (skelDecl cfg arch) (archDecls arch)

skelDecl :: GoConfig -> Architecture -> Declaration -> [(FilePath, Text)]
skelDecl cfg arch d = case declKind d of
  Model     -> skelModel cfg d
  Boundary  -> skelBoundary cfg d
  Operation -> skelOperation cfg arch d
  Adapter   -> skelAdapter cfg arch d
  Compose   -> []  -- compose is wiring, not a type

skelModel :: GoConfig -> Declaration -> [(FilePath, Text)]
skelModel cfg d =
  let pkg = maybe "domain" (layerPkg cfg) (declLayer d)
      name = exportedName (declName d)
      fields = declFields d
      body = T.unlines $
        [ "package " <> pkg
        , ""
        , "// " <> name <> " — generated from model " <> declName d
        , "type " <> name <> " struct {"
        ] ++
        [ "\t" <> exportedName fn <> " " <> goType cfg ft
        | (fn, ft) <- fields
        ] ++
        [ "}"
        ]
      fp = T.unpack pkg <> "/" <> T.unpack (fileName (declName d)) <> ".go"
  in [(fp, body)]

skelBoundary :: GoConfig -> Declaration -> [(FilePath, Text)]
skelBoundary cfg d =
  let pkg = maybe "port" (layerPkg cfg) (declLayer d)
      name = exportedName (declName d)
      ops = declOps d
      body = T.unlines $
        [ "package " <> pkg
        , ""
        , "// " <> name <> " — generated from boundary " <> declName d
        , "type " <> name <> " interface {"
        ] ++
        map (renderOpSig cfg) ops ++
        [ "}"
        ]
      fp = T.unpack pkg <> "/" <> T.unpack (fileName (declName d)) <> ".go"
  in [(fp, body)]

renderOpSig :: GoConfig -> (Text, [Param], [Param]) -> Text
renderOpSig cfg (name, ins, outs) =
  "\t" <> exportedName name <> "(" <> goParams cfg ins <> ")" <> goReturns cfg outs

goParams :: GoConfig -> [Param] -> Text
goParams cfg ps = T.intercalate ", " $ map renderParam ps
  where
    renderParam (Param pn pt) = pn <> " " <> goType cfg pt

goReturns :: GoConfig -> [Param] -> Text
goReturns _ [] = ""
goReturns cfg outs =
  let types = map (\(Param _ pt) -> goType cfg pt) outs
      hasError = any (\(Param _ pt) -> isErrorType pt) outs
      nonErr   = filter (\(Param _ pt) -> not (isErrorType pt)) outs
  in case (nonErr, hasError) of
    ([], True)  -> " error"
    ([Param _ t], True) -> " (" <> goType cfg t <> ", error)"
    (_, True)  -> " (" <> T.intercalate ", " (map (\(Param _ pt) -> goType cfg pt) nonErr) <> ", error)"
    (_, False) -> " (" <> T.intercalate ", " types <> ")"

isErrorType :: TypeExpr -> Bool
isErrorType (TRef "Error") = True
isErrorType _              = False

skelOperation :: GoConfig -> Architecture -> Declaration -> [(FilePath, Text)]
skelOperation cfg arch d =
  let pkg = maybe "usecase" (layerPkg cfg) (declLayer d)
      name = exportedName (declName d)
      ins  = [p | Input pn pt <- declBody d, let p = (pn, pt)]
      outs = [p | Output pn pt <- declBody d, let p = (pn, pt)]
      deps = declNeeds d
      depDecls = mapMaybe (\n -> lookupDecl n arch) deps
      body = T.unlines $
        [ "package " <> pkg
        , ""
        , "// " <> name <> " — generated from operation " <> declName d
        , "type " <> name <> " struct {"
        ] ++
        [ "\t" <> unexport (declName dd) <> " " <> qualifiedPort cfg dd
        | dd <- depDecls
        ] ++
        [ "}"
        , ""
        , "func New" <> name <> "(" <> ctorParams cfg depDecls <> ") *" <> name <> " {"
        , "\treturn &" <> name <> "{"
        ] ++
        [ "\t\t" <> unexport (declName dd) <> ": " <> unexport (declName dd) <> ","
        | dd <- depDecls
        ] ++
        [ "\t}"
        , "}"
        , ""
        , renderExecute cfg name ins outs
        ]
      fp = T.unpack pkg <> "/" <> T.unpack (fileName (declName d)) <> ".go"
  in [(fp, body)]

unexport :: Text -> Text
unexport t = case T.uncons t of
  Just (c, rest) -> T.cons (toLower c) rest
  Nothing        -> t

qualifiedPort :: GoConfig -> Declaration -> Text
qualifiedPort cfg dd =
  let pkg = maybe "port" (layerPkg cfg) (declLayer dd)
  in pkg <> "." <> exportedName (declName dd)

ctorParams :: GoConfig -> [Declaration] -> Text
ctorParams cfg dds = T.intercalate ", " $
  map (\dd -> unexport (declName dd) <> " " <> qualifiedPort cfg dd) dds

renderExecute :: GoConfig -> Text -> [(Text, TypeExpr)] -> [(Text, TypeExpr)] -> Text
renderExecute cfg name ins outs =
  let inParams = T.intercalate ", " [n <> " " <> goType cfg t | (n, t) <- ins]
      hasError = any (isErrorType . snd) outs
      nonErr   = filter (not . isErrorType . snd) outs
      retTypes = case (nonErr, hasError) of
        ([], True)  -> "error"
        (_, True)   -> "(" <> T.intercalate ", " (map (\(_, t) -> goType cfg t) nonErr) <> ", error)"
        (_, False)  -> "(" <> T.intercalate ", " (map (\(_, t) -> goType cfg t) outs) <> ")"
  in T.unlines
    [ "func (uc *" <> name <> ") Execute(" <> inParams <> ") " <> retTypes <> " {"
    , "\tpanic(\"TODO: implement " <> name <> "\")"
    , "}"
    ]

skelAdapter :: GoConfig -> Architecture -> Declaration -> [(FilePath, Text)]
skelAdapter cfg arch d =
  let pkg = maybe "adapter" (layerPkg cfg) (declLayer d)
      name = exportedName (declName d)
      injects = [(n, t) | Inject n t <- declBody d]
      mbImpl = findImplements (declBody d) >>= \bn -> lookupDecl bn arch
      body = T.unlines $
        [ "package " <> pkg
        , ""
        , "// " <> name <> " — generated from adapter " <> declName d
        ] ++
        (case mbImpl of
          Just impl -> ["// implements " <> declName impl]
          Nothing   -> []) ++
        [ "type " <> name <> " struct {"
        ] ++
        [ "\t" <> exportedName n <> " " <> goType cfg t
        | (n, t) <- injects
        ] ++
        [ "}"
        ]
      fp = T.unpack pkg <> "/" <> T.unpack (fileName (declName d)) <> ".go"
  in [(fp, body)]

----------------------------------------------------------------------
-- Contract test generation
----------------------------------------------------------------------

contract :: GoConfig -> Architecture -> [(FilePath, Text)]
contract cfg arch =
  let boundaries = [d | d <- archDecls arch, declKind d == Boundary]
      adapters   = [d | d <- archDecls arch, declKind d == Adapter]
  in concatMap (contractBoundary cfg arch boundaries adapters) boundaries

contractBoundary :: GoConfig -> Architecture -> [Declaration] -> [Declaration] -> Declaration -> [(FilePath, Text)]
contractBoundary cfg _arch _boundaries adapters bnd =
  let pkg = maybe "port" (layerPkg cfg) (declLayer bnd)
      name = exportedName (declName bnd)
      ops = declOps bnd
      impls = filter (\a -> findImplements (declBody a) == Just (declName bnd)) adapters
      body = T.unlines $
        [ "package " <> pkg <> "_test"
        , ""
        , "import \"testing\""
        , ""
        , "// Contract tests for " <> name
        , "// Every adapter implementing " <> name <> " must pass these tests."
        , "// Known adapters: " <> T.intercalate ", " (map declName impls)
        , ""
        , "type " <> name <> "Contract struct {"
        , "\tNew func() " <> name
        , "}"
        , ""
        ] ++
        concatMap (contractOp cfg name) ops
      fp = T.unpack pkg <> "/" <> T.unpack (fileName (declName bnd)) <> "_contract_test.go"
  in [(fp, body)]

contractOp :: GoConfig -> Text -> (Text, [Param], [Param]) -> [Text]
contractOp cfg ifaceName (opName, ins, outs) =
  let eName = exportedName opName
      hasError = any (\(Param _ pt) -> isErrorType pt) outs
      nonErr   = filter (\(Param _ pt) -> not (isErrorType pt)) outs
  in [ "func (c " <> ifaceName <> "Contract) Test" <> eName <> "(t *testing.T) {"
     , "\tadapter := c.New()"
     ] ++
     -- Generate zero-value arguments
     [ "\t" <> zeroVar cfg n t
     | Param n t <- ins
     ] ++
     [ "\t" <> callExpr eName (map paramName ins) nonErr hasError
     , if hasError
       then "\tif err != nil {\n\t\tt.Logf(\"" <> eName <> " returned error (may be expected): %v\", err)\n\t}"
       else ""
     ] ++
     [ "\t_ = adapter // ensure adapter is used"
     , "}"
     , ""
     ]

zeroVar :: GoConfig -> Text -> TypeExpr -> Text
zeroVar cfg n t = n <> " := " <> zeroValue cfg t

zeroValue :: GoConfig -> TypeExpr -> Text
zeroValue _   (TBuiltin BString)   = "\"\""
zeroValue _   (TBuiltin BInt)      = "0"
zeroValue _   (TBuiltin BFloat)    = "0.0"
zeroValue _   (TBuiltin BDecimal)  = "0.0"
zeroValue _   (TBuiltin BBool)     = "false"
zeroValue _   (TBuiltin BUnit)     = "struct{}{}"
zeroValue _   (TBuiltin BBytes)    = "nil"
zeroValue _   (TBuiltin BDateTime) = "time.Time{}"
zeroValue _   (TBuiltin BAny)      = "nil"
zeroValue cfg (TRef name)          = Map.findWithDefault (name <> "{}") name
                                       (Map.fromList [("Error", "nil"), ("error", "nil")]
                                        `Map.union` fmap (\_ -> "nil") (goTypeMap cfg))
zeroValue _   (TGeneric "List" _)  = "nil"
zeroValue _   (TGeneric "Set" _)   = "nil"
zeroValue _   (TGeneric "Map" _ )  = "nil"
zeroValue _   (TNullable _)        = "nil"
zeroValue _   _                    = "nil"

callExpr :: Text -> [Text] -> [Param] -> Bool -> Text
callExpr opName args nonErr hasError =
  let retVars = map (\(Param n _) -> n) nonErr ++ (if hasError then ["err"] else [])
      lhs = case retVars of
        [] -> ""
        _  -> T.intercalate ", " retVars <> " := "
      rhs = "adapter." <> opName <> "(" <> T.intercalate ", " args <> ")"
      suppress = T.concat ["_ = " <> v <> "; " | Param v _ <- nonErr]
  in lhs <> rhs <> "\n\t" <> suppress

----------------------------------------------------------------------
-- Compile-time verification
----------------------------------------------------------------------

verify :: GoConfig -> Architecture -> [(FilePath, Text)]
verify cfg arch =
  let adapters = [d | d <- archDecls arch, declKind d == Adapter]
      checks = concatMap (verifyAdapter cfg arch) adapters
  in if null checks then []
     else
       let body = T.unlines $
             [ "package verify"
             , ""
             , "// Generated by plat-hs — compile-time architecture conformance."
             , "// If this file fails to compile, the implementation does not"
             , "// match the architecture defined in plat-hs."
             , ""
             , "import ("
             ] ++
             verifyImports cfg arch adapters ++
             [ ")"
             , ""
             ] ++
             checks
       in [("verify/verify_architecture.go", body)]

verifyAdapter :: GoConfig -> Architecture -> Declaration -> [Text]
verifyAdapter cfg arch d = case findImplements (declBody d) of
  Nothing -> []
  Just bndName -> case lookupDecl bndName arch of
    Nothing  -> []
    Just _bnd ->
      let adpPkg = maybe "adapter" (layerPkg cfg) (declLayer d)
          bndPkg = maybe "port" (layerPkg cfg) (declLayer _bnd)
          adpType = adpPkg <> "." <> exportedName (declName d)
          bndType = bndPkg <> "." <> exportedName bndName
      in  ["var _ " <> bndType <> " = (*" <> adpType <> ")(nil)"]

verifyImports :: GoConfig -> Architecture -> [Declaration] -> [Text]
verifyImports cfg _arch adapters =
  let pkgs = concatMap adapterPkgs adapters
      uniq = Map.keys $ Map.fromList [(p, ()) | p <- pkgs]
  in map (\p -> "\t\"" <> goModule cfg <> "/" <> p <> "\"") uniq
  where
    adapterPkgs d =
      let adpPkg = maybe "adapter" (layerPkg cfg) (declLayer d)
      in adpPkg : case findImplements (declBody d) of
           Nothing -> []
           Just bndName ->
             let bndDecl = [dd | dd <- archDecls (Architecture "" [] [] [] [] []), declName dd == bndName]
             in map (\dd -> maybe "port" (layerPkg cfg) (declLayer dd)) bndDecl

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

lookupDecl :: Text -> Architecture -> Maybe Declaration
lookupDecl name arch = case [d | d <- archDecls arch, declName d == name] of
  (d:_) -> Just d
  []    -> Nothing
