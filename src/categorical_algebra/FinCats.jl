""" 2-category of finitely presented categories.

This module is to the 2-category **Cat** what the module [`FinSets](@ref) is to
the category **Set**: a finitary, combinatorial setting where explicit
computations can be carried out.
"""
module FinCats
export FinCat, FinFunctor, FinDomFunctor, Ob, nobjects, nhom_generators,
  is_functorial, ob_map, hom_map,
  Vertex, Edge, Path, graph, edges, src, tgt

using AutoHashEquals
using StaticArrays: SVector

using ...GAT
using ...Theories: Category
import ...Theories: Ob, dom, codom, id, compose, ⋅, ∘
using ...Graphs
import ...Graphs: edges, src, tgt
using ..FinSets, ..Categories

# Base types
############

""" Abstract type for finitely presented category.
"""
abstract type FinCat{Ob,Hom} <: Cat{Ob,Hom} end

""" Number of objects in finitely presented category.
"""
function nobjects end

""" Number of generating morphisms in finitely presented category.
"""
function nhom_generators end

Ob(C::FinCat{Int}) = FinSet(nobjects(C))

""" Abstract type for category with finite generating graph.
"""
abstract type FinCatGraph{Ob,Hom} <: FinCat{Ob,Hom} end

""" Generating graph for a finitely presented category.
"""
graph(C::FinCatGraph) = C.graph

nobjects(C::FinCatGraph) = nv(graph(C))
nhom_generators(C::FinCatGraph) = ne(graph(C))

""" Abstract type for functor out of a finitely presented category.
"""
abstract type FinDomFunctor{Dom<:FinCat,Codom<:Cat} end

""" Abstract type for functor between finitely presented categories.
"""
const FinFunctor{Dom,Codom<:FinCat} = FinDomFunctor{Dom,Codom}

FinFunctor(maps, dom::FinCat, codom::FinCat) = FinDomFunctor(maps, dom, codom)
FinFunctor(ob_map, hom_map, dom::FinCat, codom::FinCat) =
  FinDomFunctor(ob_map, hom_map, dom, codom)

dom(F::FinDomFunctor) = F.dom
codom(F::FinDomFunctor) = F.codom

# Free categories
#################

# Paths in graphs
#----------------

""" Vertex in a graph.

Like [`Edge`](@ref), this wrapper type is used mainly to control dispatch.
"""
@auto_hash_equals struct Vertex{T} <: AbstractArray{0,T}
  vertex::T
end
Base.getindex(v::Vertex) = v.vertex

""" Edge in a graph.

Like [`Vertex`](@ref), this wrapper type is used mainly to control dispatch.
"""
@auto_hash_equals struct Edge{T} <: AbstractArray{0,T}
  edge::T
end
Base.getindex(e::Edge) = e.edge

""" Path in a graph.

The path may be empty but always has definite start and end points (source and
target vertices).

See also: [`Vertex`](@ref), [`Edge`](@ref).
"""
@auto_hash_equals struct Path{T,Edges<:AbstractVector{T}}
  edges::Edges
  src::T
  tgt::T
end
edges(path::Path) = path.edges
src(path::Path) = path.src
tgt(path::Path) = path.tgt

function Path(g::HasGraph, es::AbstractVector)
  !isempty(es) || error("Nonempty edge list needed for nontrivial path")
  Path(es, src(g, first(es)), tgt(g, last(es)))
end

Path(g::HasGraph, e) = Path(SVector(e), src(g,e), tgt(g,e))
Path(g::HasGraph, e::Edge) = Path(g, e[])

Base.empty(::Type{Path}, v::T) where T = Path(SVector{0,T}(), v, v)
Path(v::Vertex) = empty(Path, v[])

function Base.vcat(p1::Path, p2::Path)
  tgt(p1) == src(p2) ||
    error("Path start/end points do not match: $(tgt(p1)) != $(src(p2))")
  Path(vcat(edges(p1), edges(p2)), src(p1), tgt(p2))
end

@instance Category{Vertex,Path} begin
  dom(path::Path) = Vertex(src(path))
  codom(path::Path) = Vertex(tgt(path))
  id(v::Vertex) = Path(v)
  compose(p1::Path, p2::Path) = vcat(p1, p2)
end

# Free category on graph
#-----------------------

""" Free category generated by a finite graph.

The objects of the free category are vertices in the graph and the morphisms are
(possibly empty) paths.
"""
struct FreeFinCatGraph{G<:HasGraph} <: FinCatGraph{Int,Path{Int}}
  graph::G
end

FinCat(g::HasGraph) = FreeFinCatGraph(g)

function is_functorial(F::FinFunctor{<:FinCatGraph})
  g = graph(dom(F))
  all(edges(g)) do e
    f = hom_map(F, e)
    src(f) == ob_map(F, src(g,e)) && tgt(f) == ob_map(F, tgt(g,e))
  end
end

""" Vector-based functor out of a finitely presented category.
"""
@auto_hash_equals struct FinDomFunctorVector{
    VMap <: AbstractVector, EMap <: AbstractVector,
    Dom <: FinCat{Int}, Codom} <: FinDomFunctor{Dom,Codom}
  vmap::VMap
  emap::EMap
  dom::Dom
  codom::Codom

  function FinDomFunctorVector(vmap::AbstractVector, emap::AbstractVector,
                               dom::Dom, codom::Codom) where {Dom,Codom}
    length(vmap) == nobjects(dom) ||
      error("Length of object map $vmap does not match domain $dom")
    length(emap) == nhom_generators(dom) ||
      error("Length of morphism map $emap does not match domain $dom")
    vmap = map(x -> coerce_ob(codom, x), vmap)
    emap = map(f -> coerce_hom(codom, f), emap)
    new{typeof(vmap),typeof(emap),Dom,Codom}(vmap, emap, dom, codom)
  end
end

coerce_ob(C::Cat, x) = x
coerce_ob(C::FinCatGraph, v::Vertex) = v[]
coerce_hom(C::Cat, f) = f
coerce_hom(C::FinCatGraph, path::Path) = path
coerce_hom(C::FinCatGraph, f) = Path(graph(C), f)

FinDomFunctor(maps::NamedTuple{(:V,:E)}, args...) =
  FinDomFunctor(maps.V, maps.E, args...)
FinDomFunctor(vmap::AbstractVector, emap::AbstractVector, dom, codom) =
  FinDomFunctorVector(vmap, emap, dom, codom)
FinDomFunctor(vmap::AbstractVector{Ob}, emap::AbstractVector{Hom}, dom) where
  {Ob,Hom} = FinDomFunctorVector(vmap, emap, dom, TypeCat{Ob,Hom}())

ob_map(F::FinDomFunctorVector, v) = F.vmap[v]
ob_map(F::FinDomFunctorVector, v::Vertex) = Vertex(F.vmap[v[]])

hom_map(F::FinDomFunctorVector, e) = F.emap[e]
hom_map(F::FinDomFunctorVector, e::Edge) = F.emap[e[]]
hom_map(F::FinDomFunctorVector, path::Path) =
  mapreduce(e -> hom_map(F, e), compose, edges(path),
            init=id(ob_map(F, dom(path))))

(F::FinDomFunctorVector)(x::Vertex) = ob_map(F, x)
(F::FinDomFunctorVector)(f::Union{Edge,Path}) = hom_map(F, f)

Ob(F::FinDomFunctorVector) = FinDomFunction(F.vmap, Ob(codom(F)))

end
