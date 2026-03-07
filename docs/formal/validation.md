# plat Formal Validation Rules

Each validation rule is a decidable predicate over the finite structure `Architecture`.

## Notation

```
A : Architecture
D : Declaration
I : DeclItem
P(A) = { d | d in archDecls(A), P(d) }
```

## Core Rules

### V001: Declaration name uniqueness
```
V001(A) = forall d1, d2 in archDecls(A):
  d1 /= d2 => declName(d1) /= declName(d2)
```
**Severity**: Error

### V002: Layer DAG (no cycles)
```
V002(A) = isAcyclic(layer dependency graph of archLayers(A))
       = cyclicGroups(archLayers(A)) = []
```
**Severity**: Error
**Algorithm**: Tarjan SCC via `Data.Graph.stronglyConnComp`, O(V+E)

### V003: Operation must reference existing Boundary
```
V003(A) = forall d in archDecls(A), Needs(n) in declBody(d):
  n in { declName(b) | b in archDecls(A), declKind(b) = Boundary }
```
**Severity**: Error

### V004: Adapter implements existing Boundary
```
V004(A) = forall d in archDecls(A), Implements(n) in declBody(d):
  n in { declName(b) | b in archDecls(A), declKind(b) = Boundary }
```
**Severity**: Error

### V005: Layer reference validity
```
V005(A) = forall d in archDecls(A):
  declKind(d) /= Compose =>
    declLayer(d) in { Just(layerName(l)) | l in archLayers(A) }
```
**Severity**: Error

### V006: DeclItem-DeclKind consistency
```
V006(A) = forall d in archDecls(A):
  forall item in declBody(d):
    item is allowed by kinding rules for declKind(d)
```
**Severity**: Error

### V007: Adapter covers Boundary operations
```
V007(A) = forall d in archDecls(A), Implements(bnd) in declBody(d):
  let boundaryOps = { name | Op(name, _, _) in declBody(b), declName(b) = bnd }
  let adapterOps  = { name | Op(name, _, _) in declBody(d) }
  in adapterOps = {} \/ boundaryOps ⊆ adapterOps
```
**Note**: Empty adapter ops = implicit full coverage (design decision)

### V008: Bind coherence
```
V008(A) = forall d in archDecls(A), Bind(bnd, adp) in declBody(d):
  bnd in declNames(A) /\ adp in declNames(A)
  /\ Implements(bnd) in declBody(lookup(adp, A))
```
**Severity**: Error

### V009: ArchConstraint satisfaction
```
V009(A) = forall c in archConstraints(A):
  acCheck(c)(A) = []
```
**Severity**: Error

## Warning Rules

### W001: Unused Boundary (no adapter implements it)
```
W001(A) = forall b in archDecls(A), declKind(b) = Boundary:
  exists a in archDecls(A): Implements(declName(b)) in declBody(a)
```

### W002: Unresolved type reference
```
W002(A) = forall d in archDecls(A):
  forall TRef(n) in typeRefs(declBody(d)):
    n in declNames(A) \/ n in aliasNames(A) \/ n in customTypes(A)
```
**Note**: `TExt` and types inside `Inject` are excluded

### W003: Multiple adapters implementing same Boundary
```
W003(A) = forall b in boundaries(A):
  |{ a | a in adapters(A), Implements(declName(b)) in declBody(a) }| <= 1
```

### W004: Source file existence
```
W004(A) = forall d in archDecls(A):
  forall p in declPaths(d):
    fileExists(p)
```
**Note**: IO check, separate from pure structural validation

## Extension Rules (selected)

### CA-V001: CleanArch impl requires implements
```
CA-V001(A) = forall d in archDecls(A):
  isTagged(caImpl, d) => findImplements(declBody(d)) /= Nothing
```

### CA-V002: Inward dependency rule
```
CA-V002(A) = forall r in relations(A):
  relKind(r) in {"needs", "references"} =>
    not (isInner(layer(relSource(r))) /\ isOuter(layer(relTarget(r))))
where
  isInner(l) = l in {"enterprise", "interface"}
  isOuter(l) = l in {"framework", "application"}
```

### CQRS-V001: Command has no output
```
CQRS-V001(A) = forall d in archDecls(A):
  isCommand(d) => { () | Output _ _ <- declBody(d) } = {}
```

### MOD-V003: Unexposed reference
```
MOD-V003(A) = forall (src, tgt) in allRefs(A):
  ownerModule(src) /= ownerModule(tgt) =>
    tgt in exposedBy(ownerModule(tgt))
```

## Decidability

All rules are decidable predicates over finite structures:
- `archDecls` is a finite list
- `relations` is computed from finite data
- `cyclicGroups` terminates in O(V+E) via Tarjan SCC
- No rule requires fixpoint computation over unbounded domains

This guarantees that `check :: Architecture -> [Diagnostic]` always terminates.
