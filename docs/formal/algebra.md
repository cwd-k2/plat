# plat Architecture Algebra

## Algebraic Structure

The `Architecture` type forms a partial commutative monoid under `merge`,
with `project` acting as a forgetful endomorphism.

## Operations

### merge : Architecture x Architecture -> Either [Conflict] Architecture

Combines two architectures if they are compatible.

```
merge(A, B) = Right(C) where
  archLayers(C)  = archLayers(A) ∪ archLayers(B)       (with compatibility check)
  archDecls(C)   = archDecls(A) ∪ archDecls(B)         (with conflict check)
  archRelations(C) = archRelations(A) ∪ archRelations(B)
  ...

merge(A, B) = Left(conflicts) when
  exists d in archDecls(A) ∩ archDecls(B):
    declKind(d_A) /= declKind(d_B)
    \/ declLayer(d_A) /= declLayer(d_B)
```

**Compatibility**: Two declarations with the same name are compatible iff
they have the same `declKind` and `declLayer`. Their bodies are merged
(union of items).

### project : (Declaration -> Bool) -> Architecture -> Architecture

Filters declarations by predicate and removes orphaned relations.

```
project(P, A) = A' where
  archDecls(A')     = { d | d in archDecls(A), P(d) }
  archRelations(A') = { r | r in archRelations(A),
                         relSource(r) in names(A'),
                         relTarget(r) in names(A') }
```

Convenience projections:
- `projectLayer(l, A) = project(\d -> declLayer(d) == Just l, A)`
- `projectKind(k, A) = project(\d -> declKind(d) == k, A)`

### diff : Architecture -> Architecture -> ArchDiff

Structural change detection between two architectures.

```
diff(A, B) = ArchDiff {
  added   = { declName(d) | d in archDecls(B), declName(d) not in names(A) }
  removed = { declName(d) | d in archDecls(A), declName(d) not in names(B) }
  changed = { (declName(d), delta) | d in both, d_A /= d_B }
}
```

### mergeAll : [Architecture] -> Either [Conflict] Architecture

Left fold of `merge`.

```
mergeAll([])    = Right(empty)
mergeAll(a:as)  = merge(a, mergeAll(as))
```

## Algebraic Properties

### Commutativity (partial)
```
merge(A, B) = merge(B, A)
```
When both succeed, the result is identical (up to ordering of lists).

### Associativity (partial)
```
merge(A, merge(B, C)) = merge(merge(A, B), C)
```
When all intermediate merges succeed.

### Identity
```
merge(A, empty) = Right(A)
merge(empty, A) = Right(A)
```

### project is idempotent
```
project(P, project(P, A)) = project(P, A)
```

### project preserves constraints (vacuous truth)
```
archConstraints(project(P, A)) = archConstraints(A)

forall c in archConstraints(A):
  let A' = project(P, A)
  in  acCheck(c)(A') evaluates over archDecls(A')
  -- Constraints using require/forbid/forAll are vacuously true
  -- for declaration kinds that are projected away, because the
  -- quantified set becomes empty.
```

### project distributes over merge
```
project(P, merge(A, B)) = merge(project(P, A), project(P, B))
```
When the merge succeeds.

### diff is antisymmetric
```
diff(A, B).added = diff(B, A).removed
diff(A, B).removed = diff(B, A).added
```

## Categorical View

| plat operation | Category theory analogue |
|---------------|-------------------------|
| `merge`       | Colimit (pushout) in Arch |
| `project`     | Image of a forgetful functor |
| `diff`        | Structural change morphism |
| `Architecture` | Object in Arch |
| `isCompatible` | Existence of colimit |

The category **Arch** has:
- Objects: well-formed `Architecture` values
- Morphisms: structure-preserving maps (embeddings via `project`)
- `merge` as a partial binary coproduct

## Metrics as Functors

The `metrics` function defines a functor from **Arch** to **Met** (metric space):

```
metrics : Architecture -> Metrics
metrics(A) = { mDeclMetrics = ..., mAbstractness = ... }
```

Key property: `metrics` is monotone with respect to merge:
```
Ce(d, merge(A, B)) >= Ce(d, A)
Ca(d, merge(A, B)) >= Ca(d, A)
```
Adding declarations can only increase coupling, never decrease it.
