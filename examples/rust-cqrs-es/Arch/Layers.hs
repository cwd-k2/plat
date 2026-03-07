module Arch.Layers (dom, app, infra) where

import Plat.Core

dom :: LayerDef
dom = layer "domain"

app :: LayerDef
app = layer "application" `depends` [dom]

infra :: LayerDef
infra = layer "infrastructure" `depends` [dom, app]
