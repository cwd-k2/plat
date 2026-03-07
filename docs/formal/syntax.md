# plat Formal Syntax

## Abstract Syntax (BNF)

```
Architecture ::= Arch(name, [Layer], [TypeAlias], [Declaration], [Constraint], [Relation])

Layer    ::= Layer(name, [name])           -- name, dependency list
TypeAlias ::= Alias(name, TypeExpr)

Declaration ::= Decl(DeclKind, name, layer?, [DeclItem], [(key, value)])

DeclKind ::= Model | Boundary | Operation | Adapter | Compose

DeclItem ::= Field(name, TypeExpr)
           | Op(name, [Param], [Param])    -- name, inputs, outputs
           | Input(name, TypeExpr)
           | Output(name, TypeExpr)
           | Needs(name)
           | Implements(name)
           | Inject(name, TypeExpr)
           | Bind(name, name)              -- boundary, adapter
           | Entry(name)

Param    ::= Param(name, TypeExpr)

TypeExpr ::= TBuiltin(Builtin)
           | TRef(name)
           | TGeneric(name, [TypeExpr])
           | TNullable(TypeExpr)
           | TExt(name)

Builtin  ::= String | Int | Float | Decimal | Bool | Unit | Bytes | DateTime | Any
```

## Kinding Rules

The phantom tag `k :: DeclKind` constrains which `DeclItem` constructors are
available in a `DeclWriter k` computation:

```
k = Model     |- field, meta, path
k = Boundary  |- op, meta, path
k = Operation |- input, output, needs, meta, path
k = Adapter   |- inject, implements, meta, path
k = Compose   |- bind, entry, meta
```

These are enforced at the Haskell type level via the `HasPath` class and
by restricting each combinator's type signature:

```
field      :: Text -> TypeExpr -> DeclWriter 'Model ()
op         :: Text -> [Param] -> [Param] -> DeclWriter 'Boundary ()
input      :: Text -> TypeExpr -> DeclWriter 'Operation ()
output     :: Text -> TypeExpr -> DeclWriter 'Operation ()
needs      :: Decl 'Boundary -> DeclWriter 'Operation ()
implements :: Decl 'Boundary -> DeclWriter 'Adapter ()
inject     :: Text -> TypeExpr -> DeclWriter 'Adapter ()
bind       :: Decl 'Boundary -> Decl 'Adapter -> DeclWriter 'Compose ()
entry      :: Decl k -> DeclWriter 'Compose ()
```

The `meta`, `tagAs`, `annotate`, `refer`, `attr` combinators are
polymorphic in `k` and available in all declaration kinds.

## Well-formedness Judgments

An `Architecture` is **well-formed** iff all of the following hold:

### WF-Layers: Layer DAG
```
forall l in archLayers:
  forall d in layerDeps(l):
    exists l' in archLayers: layerName(l') = d
  /\ not (reachable(l, l) in layer dependency graph)
```

### WF-Names: Unique declaration names
```
forall d1, d2 in archDecls:
  d1 /= d2 => declName(d1) /= declName(d2)
```

### WF-Layers-Assigned: Layer assignment
```
forall d in archDecls:
  declKind(d) /= Compose =>
    exists l in archLayers: declLayer(d) = Just(layerName(l))
```

### WF-Refs: Type reference validity
```
forall d in archDecls:
  forall TRef(n) in typeRefs(d):
    exists d' in archDecls: declName(d') = n
    \/ exists a in archTypes: aliasName(a) = n
    \/ n in archCustomTypes
```

### WF-Needs: Needs target is a Boundary
```
forall d in archDecls, Needs(n) in declBody(d):
  exists b in archDecls: declName(b) = n /\ declKind(b) = Boundary
```

### WF-Implements: Implements target is a Boundary
```
forall d in archDecls, Implements(n) in declBody(d):
  exists b in archDecls: declName(b) = n /\ declKind(b) = Boundary
```

### WF-Binds: Bind coherence
```
forall Bind(bnd, adp) in declBody(d) where declKind(d) = Compose:
  exists b in archDecls: declName(b) = bnd /\ declKind(b) = Boundary
  /\ exists a in archDecls: declName(a) = adp /\ declKind(a) = Adapter
  /\ Implements(bnd) in declBody(a)
```

### WF-Rel: Relation reference validity
```
forall r in archRelations:
  exists d in archDecls: declName(d) = relSource(r)
  /\ exists d' in archDecls: declName(d') = relTarget(r)
```
