module Arch.Layers (dom, app, port_, adp) where

import Plat.Core

dom :: LayerDef
dom = layer "domain"

app :: LayerDef
app = layer "application" `depends` [dom, port_]

port_ :: LayerDef
port_ = layer "port" `depends` [dom]

adp :: LayerDef
adp = layer "adapter" `depends` [dom, port_, app]
