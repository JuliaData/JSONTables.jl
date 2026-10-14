module JSONTables

using JSON, Tables
using JSON: StructUtils

export jsontable, arraytable, objecttable

# read

struct Table{columnar, T}
    names::Vector{Symbol}
    types::Dict{Symbol, Type}
    source::T
end

jsontable(source; kwargs...) = jsontable(JSON.parse(source; kwargs...))
jsontable(source::AbstractVector{UInt8}; kwargs...) = jsontable(JSON.parse(source; kwargs...))

missT(::Type{Nothing}) = Missing
missT(::Type{T}) where {T} = T

# widen column type `T` to also hold value `v`, with JSON null read as `missing`
function widen(::Type{T}, v) where {T}
    S = missT(typeof(v))
    return S <: T ? T : Union{T, S}
end

# objects may be keyed by `Symbol` (e.g. JSON3.jl) or by `String` (JSON.jl)
key(::AbstractDict{Symbol}, nm::Symbol) = nm
key(::AbstractDict, nm::Symbol) = String(nm)

function jsontable(x::AbstractDict)
    names = Symbol[]
    types = Dict{Symbol, Type}()
    len = 0
    for (k, v) in x
        v isa AbstractVector || throw(ArgumentError("input JSON object must only have array values to be considered a table"))
        (isempty(names) || len == length(v)) || throw(ArgumentError("all JSON array values must have the same length to be a valid table"))
        nm = Symbol(k)
        push!(names, nm)
        len = length(v)
        T = Union{}
        for y in v
            T = widen(T, y)
        end
        types[nm] = T === Union{} ? Any : T
    end
    return Table{true, typeof(x)}(names, types, x)
end

function jsontable(x::AbstractVector)
    eltype(x) <: AbstractDict || (!isempty(x) && all(row -> row isa AbstractDict, x)) ||
        throw(ArgumentError("input JSON array must only have object elements to be considered a table"))
    names = Symbol[]
    seen = Set{Symbol}()
    types = Dict{Symbol, Type}()
    for (row_number, row) in enumerate(x)
        if row_number == 1
            for (k, v) in row
                push!(names, Symbol(k))
                types[Symbol(k)] = missT(typeof(v))
            end
            seen = Set(names)
        else
            for nm in names
                k = key(row, nm)
                types[nm] = haskey(row, k) ? widen(types[nm], row[k]) : Union{Missing, types[nm]}
            end
            for (k, v) in row
                nm = Symbol(k)
                if !(nm in seen)
                    push!(seen, nm)
                    push!(names, nm)
                    types[nm] = Union{Missing, missT(typeof(v))}
                end
            end
        end
    end
    return Table{false, typeof(x)}(names, types, x)
end

Tables.istable(::Type{<:Table}) = true
Tables.schema(x::Table) = Tables.Schema(getfield(x, :names), [getfield(x, :types)[nm] for nm in getfield(x, :names)])

# columnar source
Tables.columnaccess(::Type{Table{true, T}}) where {T} = true
Tables.columns(x::Table{true}) = x

miss(x) = ifelse(x === nothing, missing, x)
struct MissingVector{T, S<:AbstractVector} <: AbstractVector{T}
    x::S
end
MissingVector{T}(x::S) where {T, S} = MissingVector{T, S}(x)
Base.IndexStyle(::Type{<:MissingVector}) = Base.IndexLinear()
Base.size(x::MissingVector) = size(x.x)
@inline Base.getindex(x::MissingVector, i::Int) = miss(x.x[i])

Base.propertynames(x::Table{true}) = Tuple(getfield(x, :names))
function Base.getproperty(x::Table{true}, nm::Symbol)
    source = getfield(x, :source)
    return MissingVector{getfield(x, :types)[nm]}(source[key(source, nm)])
end

Tables.columnnames(x::Table{true}) = propertynames(x)
Tables.getcolumn(x::Table{true}, i::Int) = getproperty(x, propertynames(x)[i])
Tables.getcolumn(x::Table{true}, nm::Symbol) = getproperty(x, nm)

# row source
Tables.rowaccess(::Type{Table{false, T}}) where {T} = true
Tables.rows(x::Table{false}) = x

Base.IteratorSize(::Type{Table{false, T}}) where {T} = Base.HasLength()
Base.length(x::Table{false}) = length(x.source)

struct MissingRow{T} <: Tables.AbstractRow
    names::Vector{Symbol}
    x::T
end

function getmiss(x, nm)
    k = key(x, nm)
    return haskey(x, k) ? miss(x[k]) : missing
end
Tables.columnnames(x::MissingRow) = getfield(x, :names)
Tables.getcolumn(x::MissingRow, nm::Symbol) = getmiss(getfield(x, :x), nm)
Tables.getcolumn(x::MissingRow, i::Int) = getmiss(getfield(x, :x), getfield(x, :names)[i])

@inline function Base.iterate(x::Table{false}, st=())
    st = iterate(x.source, st...)
    st === nothing && return nothing
    val, state = st
    return MissingRow(x.names, val), (state,)
end

# write

# a table row, or a table's columns, written as a JSON object of name => value
struct JSONObject{T}
    x::T
end

StructUtils.dictlike(::Type{<:JSONObject}) = true

function StructUtils.applyeach(st::StructUtils.StructStyle, f, x::JSONObject)
    for nm in Tables.columnnames(x.x)
        ret = f(StructUtils.lowerkey(st, nm), StructUtils.lower(st, Tables.getcolumn(x.x, nm)))
        ret isa StructUtils.EarlyReturn && return ret
    end
    return StructUtils.defaultstate(st)
end

arrayrows(table) = (JSONObject(row) for row in Tables.rows(table))

objecttable(table) = JSON.json(JSONObject(Tables.columns(table)))
objecttable(io::IO, table) = JSON.json(io, JSONObject(Tables.columns(table)))
arraytable(table) = JSON.json(arrayrows(table))
arraytable(io::IO, table) = JSON.json(io, arrayrows(table))

end # module
