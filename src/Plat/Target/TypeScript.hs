-- | TypeScript code generation: skeleton, contract tests, compile-time verification.
module Plat.Target.TypeScript
  ( TsConfig (..)
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

data TsConfig = TsConfig
  { tsTypeMap  :: Map.Map Text Text   -- ^ Custom type overrides
  , tsLayerDir :: Map.Map Text Text   -- ^ Layer → directory name overrides
  }

defaultConfig :: TsConfig
defaultConfig = TsConfig
  { tsTypeMap  = Map.fromList [("Error", "Error")]
  , tsLayerDir = Map.empty
  }

----------------------------------------------------------------------
-- Type mapping
----------------------------------------------------------------------

layerDir :: TsConfig -> Text -> Text
layerDir cfg ly = Map.findWithDefault ly ly (tsLayerDir cfg)

tsType :: TsConfig -> TypeExpr -> Text
tsType _   (TBuiltin BString)   = "string"
tsType _   (TBuiltin BInt)      = "number"
tsType _   (TBuiltin BFloat)    = "number"
tsType _   (TBuiltin BDecimal)  = "number"
tsType _   (TBuiltin BBool)     = "boolean"
tsType _   (TBuiltin BUnit)     = "void"
tsType _   (TBuiltin BBytes)    = "Uint8Array"
tsType _   (TBuiltin BDateTime) = "Date"
tsType _   (TBuiltin BAny)      = "unknown"
tsType cfg (TRef name)          = Map.findWithDefault name name (tsTypeMap cfg)
tsType cfg (TGeneric "List" [t])     = tsType cfg t <> "[]"
tsType cfg (TGeneric "Set" [t])      = "Set<" <> tsType cfg t <> ">"
tsType cfg (TGeneric "Map" [k, v])   = "Map<" <> tsType cfg k <> ", " <> tsType cfg v <> ">"
tsType cfg (TGeneric "Option" [t])   = tsType cfg t <> " | null"
tsType cfg (TGeneric "Result" [t, _]) = tsType cfg t  -- TS uses throw
tsType cfg (TGeneric "Stream" [t])   = "AsyncIterable<" <> tsType cfg t <> ">"
tsType cfg (TGeneric "Id" [t])       = tsType cfg t <> "Id"
tsType cfg (TGeneric n ts)           = n <> "<" <> T.intercalate ", " (map (tsType cfg) ts) <> ">"
tsType cfg (TNullable t)             = tsType cfg t <> " | null"

----------------------------------------------------------------------
-- Name conventions
----------------------------------------------------------------------

toKebab :: Text -> Text
toKebab = T.pack . go . T.unpack
  where
    go [] = []
    go (c:cs)
      | isUpper c = '-' : toLower c : go cs
      | otherwise = c : go cs

fileBase :: Text -> Text
fileBase t = case T.uncons (toKebab t) of
  Just ('-', rest) -> rest
  _                -> toKebab t

camel :: Text -> Text
camel t = case T.uncons t of
  Just (c, rest) -> T.cons (toLower c) rest
  Nothing        -> t

----------------------------------------------------------------------
-- Skeleton generation
----------------------------------------------------------------------

skeleton :: TsConfig -> Architecture -> [(FilePath, Text)]
skeleton cfg arch = concatMap (skelDecl cfg arch) (archDecls arch)

skelDecl :: TsConfig -> Architecture -> Declaration -> [(FilePath, Text)]
skelDecl cfg arch d = case declKind d of
  Model     -> skelModel cfg d
  Boundary  -> skelBoundary cfg d
  Operation -> skelOperation cfg arch d
  Adapter   -> skelAdapter cfg arch d
  Compose   -> []

skelModel :: TsConfig -> Declaration -> [(FilePath, Text)]
skelModel cfg d =
  let dir = maybe "domain" (layerDir cfg) (declLayer d)
      name = declName d
      fields = declFields d
      body = T.unlines $
        [ "// Generated from model " <> name
        , "export interface " <> name <> " {"
        ] ++
        [ "  " <> camel fn <> ": " <> tsType cfg ft <> ";"
        | (fn, ft) <- fields
        ] ++
        [ "}"
        ]
      fp = T.unpack dir <> "/" <> T.unpack (fileBase name) <> ".ts"
  in [(fp, body)]

skelBoundary :: TsConfig -> Declaration -> [(FilePath, Text)]
skelBoundary cfg d =
  let dir = maybe "port" (layerDir cfg) (declLayer d)
      name = declName d
      ops = declOps d
      body = T.unlines $
        [ "// Generated from boundary " <> name
        , "export interface " <> name <> " {"
        ] ++
        map (renderOpSig cfg) ops ++
        [ "}"
        ]
      fp = T.unpack dir <> "/" <> T.unpack (fileBase name) <> ".ts"
  in [(fp, body)]

renderOpSig :: TsConfig -> (Text, [Param], [Param]) -> Text
renderOpSig cfg (name, ins, outs) =
  let params = T.intercalate ", " [camel pn <> ": " <> tsType cfg pt | Param pn pt <- ins]
      retType = tsReturnType cfg outs
  in "  " <> camel name <> "(" <> params <> "): Promise<" <> retType <> ">;"

tsReturnType :: TsConfig -> [Param] -> Text
tsReturnType _ [] = "void"
tsReturnType cfg outs =
  let nonErr = filter (\(Param _ pt) -> not (isErrorType pt)) outs
  in case nonErr of
    []              -> "void"
    [Param _ t]     -> tsType cfg t
    _               -> "{ " <> T.intercalate "; " [camel n <> ": " <> tsType cfg t | Param n t <- nonErr] <> " }"

isErrorType :: TypeExpr -> Bool
isErrorType (TRef "Error") = True
isErrorType _              = False

skelOperation :: TsConfig -> Architecture -> Declaration -> [(FilePath, Text)]
skelOperation cfg arch d =
  let dir = maybe "application" (layerDir cfg) (declLayer d)
      name = declName d
      ins  = [(pn, pt) | Input pn pt <- declBody d]
      outs = [Param pn pt | Output pn pt <- declBody d]
      deps = declNeeds d
      depDecls = mapMaybe (\n -> lookupDecl n arch) deps
      retType = tsReturnType cfg outs
      body = T.unlines $
        [ "// Generated from operation " <> name
        , ""
        , "export class " <> name <> " {"
        , "  constructor("
        ] ++
        [ "    private " <> camel (declName dd) <> ": " <> declName dd <> ","
        | dd <- depDecls
        ] ++
        [ "  ) {}"
        , ""
        , "  async execute(input: {"
        ] ++
        [ "    " <> camel n <> ": " <> tsType cfg t <> ";"
        | (n, t) <- ins
        ] ++
        [ "  }): Promise<" <> retType <> "> {"
        , "    throw new Error(\"TODO: implement " <> name <> "\");"
        , "  }"
        , "}"
        ]
      fp = T.unpack dir <> "/" <> T.unpack (fileBase name) <> ".ts"
  in [(fp, body)]

skelAdapter :: TsConfig -> Architecture -> Declaration -> [(FilePath, Text)]
skelAdapter cfg arch d =
  let dir = maybe "adapter" (layerDir cfg) (declLayer d)
      name = declName d
      injects = [(n, t) | Inject n t <- declBody d]
      mbImpl = findImplements (declBody d) >>= \bn -> lookupDecl bn arch
      implClause = case mbImpl of
        Just impl -> " implements " <> declName impl
        Nothing   -> ""
      body = T.unlines $
        [ "// Generated from adapter " <> name
        , ""
        , "export class " <> name <> implClause <> " {"
        , "  constructor("
        ] ++
        [ "    private " <> camel n <> ": " <> tsType cfg t <> ","
        | (n, t) <- injects
        ] ++
        [ "  ) {}"
        ] ++
        -- Generate method stubs for implemented boundary
        (case mbImpl of
          Nothing -> []
          Just impl ->
            concatMap (adapterMethodStub cfg) (declOps impl)) ++
        [ "}"
        ]
      fp = T.unpack dir <> "/" <> T.unpack (fileBase name) <> ".ts"
  in [(fp, body)]

adapterMethodStub :: TsConfig -> (Text, [Param], [Param]) -> [Text]
adapterMethodStub cfg (name, ins, outs) =
  let params = T.intercalate ", " [camel pn <> ": " <> tsType cfg pt | Param pn pt <- ins]
      retType = tsReturnType cfg outs
  in [ ""
     , "  async " <> camel name <> "(" <> params <> "): Promise<" <> retType <> "> {"
     , "    throw new Error(\"TODO: implement " <> name <> "\");"
     , "  }"
     ]

----------------------------------------------------------------------
-- Contract tests
----------------------------------------------------------------------

contract :: TsConfig -> Architecture -> [(FilePath, Text)]
contract cfg arch =
  let boundaries = [d | d <- archDecls arch, declKind d == Boundary]
      adapters   = [d | d <- archDecls arch, declKind d == Adapter]
  in map (contractBoundary cfg adapters) boundaries

contractBoundary :: TsConfig -> [Declaration] -> Declaration -> (FilePath, Text)
contractBoundary cfg adapters bnd =
  let dir = maybe "port" (layerDir cfg) (declLayer bnd)
      name = declName bnd
      ops = declOps bnd
      impls = filter (\a -> findImplements (declBody a) == Just (declName bnd)) adapters
      body = T.unlines $
        [ "// Contract tests for " <> name
        , "// Known adapters: " <> T.intercalate ", " (map declName impls)
        , ""
        , "export function test" <> name <> "Contract("
        , "  factory: () => " <> name <> ","
        , "  describe: (name: string, fn: () => void) => void,"
        , "  it: (name: string, fn: () => Promise<void>) => void,"
        , ") {"
        , "  describe(\"" <> name <> " contract\", () => {"
        ] ++
        concatMap (contractOp cfg name) ops ++
        [ "  });"
        , "}"
        ]
      fp = T.unpack dir <> "/" <> T.unpack (fileBase name) <> ".contract.ts"
  in (fp, body)

contractOp :: TsConfig -> Text -> (Text, [Param], [Param]) -> [Text]
contractOp _cfg _ifaceName (opName, _ins, _outs) =
  [ "    it(\"should implement " <> camel opName <> "\", async () => {"
  , "      const adapter = factory();"
  , "      // Verify method exists and is callable"
  , "      if (typeof adapter." <> camel opName <> " !== \"function\") {"
  , "        throw new Error(\"" <> camel opName <> " is not a function\");"
  , "      }"
  , "    });"
  ]

----------------------------------------------------------------------
-- Compile-time verification
----------------------------------------------------------------------

verify :: TsConfig -> Architecture -> [(FilePath, Text)]
verify cfg arch =
  let adapters = [(d, bnd) | d <- archDecls arch, declKind d == Adapter,
                  Just bndName <- [findImplements (declBody d)],
                  Just bnd <- [lookupDecl bndName arch]]
  in if null adapters then []
     else
       let body = T.unlines $
             [ "// Generated by plat-hs — compile-time architecture conformance."
             , "// If this file fails to compile (tsc --noEmit), the implementation"
             , "// does not match the architecture."
             , ""
             ] ++
             concatMap (verifyPair cfg) adapters
       in [("verify/verify_architecture.ts", body)]

verifyPair :: TsConfig -> (Declaration, Declaration) -> [Text]
verifyPair _cfg (adp, bnd) =
  [ "// " <> declName adp <> " implements " <> declName bnd
  , "const _check_" <> camel (declName adp) <> ": " <> declName bnd <> " = null! as " <> declName adp <> ";"
  , ""
  ]

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

lookupDecl :: Text -> Architecture -> Maybe Declaration
lookupDecl name arch = case [d | d <- archDecls arch, declName d == name] of
  (d:_) -> Just d
  []    -> Nothing
