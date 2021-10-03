module JSONTables

using StructTypes, JSON3, Tables

export jsontable, arraytable, objecttable

# read

struct Table{columnar, T}
    names::Vector{Symbol}
    types::Dict{Symbol, Type}
    source::T
end

jsontable(source) = jsontable(JSON3.read(source))

misselT(::Type{T}) where {T} = T
misselT(::Type{Union{Nothing, T}}) where {T} = Union{Missing, T}

function jsontable(x::JSON3.Object)
    names = Symbol[]
    types = Dict{Symbol, Type}()
    len = 0
    for (k, v) in x
        push!(names, k)
        v isa JSON3.Array || throw(ArgumentError("input `JSON3.Object` must only have `JSON3.Array` values to be considered a table"))
        (len == 0 || len == length(v)) || throw(ArgumentError("all value `JSON3.Array`s must have the same length to be a valid table"))
        len = length(v)
        types[k] = misselT(eltype(v))
    end
    return Table{true, typeof(x)}(names, types, x)
end

jsontable(x::JSON3.Array) = throw(ArgumentError("input `JSON3.Array` must only have `JSON3.Object` elements to be considered a table"))
missT(::Type{Nothing}) = Missing
missT(::Type{T}) where {T} = T

function jsontable(x::JSON3.Array{JSON3.Object})
    names = Symbol[]
    seen = Set{Symbol}()
    types = Dict{Symbol, Type}()
    for row in x
        if isempty(names)
            for (k, v) in row
                push!(names, k)
                types[k] = missT(typeof(v))
            end
            seen = Set(names)
        else
            for nm in names
                if haskey(row, nm)
                    T = types[nm]
                    v = row[nm]
                    if !(missT(typeof(v)) <: T)
                        types[nm] = Union{T, missT(typeof(v))}
                    end
                else
                    types[nm] = Union{Missing, types[nm]}
                end
            end
            for (k, v) in row
                if !(k in seen)
                    push!(seen, k)
                    push!(names, k)
                    types[k] = missT(typeof(v))
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
struct MissingVector{T} <: AbstractVector{T}
    x::T
end
Base.IndexStyle(::Type{<:MissingVector}) = Base.IndexLinear()
Base.size(x::MissingVector) = size(x.x)
@inline Base.getindex(x::MissingVector, i::Int) = miss(x.x[i])
Base.copy(x::MissingVector) = map(y->y isa JSON3.Object || y isa JSON3.Array ? copy(y) : miss(y), x)

Base.propertynames(x::Table{true}) = Tuple(keys(getfield(x, :source)))
Base.getproperty(x::Table{true}, nm::Symbol) = MissingVector(getproperty(getfield(x, :source), nm))

Tables.columnnames(x::Table{true}) = propertynames(x)
Tables.getcolumn(x::Table{true}, i::Int) = getproperty(x, propertynames(x)[i])
Tables.getcolumn(x::Table{true}, nm::Symbol) = getproperty(x, nm)

# row source
Tables.rowaccess(::Type{Table{false, T}}) where {T} = true
Tables.rows(x::Table{false}) = x

Base.IteratorSize(::Type{Table{false, T}}) where {T} = Base.HasLength()
Base.length(x::Table{false}) = length(x.source)
Base.IteratorEltype(::Type{Table{false, T}}) where {T} = Base.HasEltype()
Base.eltype(x::Table{false, JSON3.Array{T}}) where {T} = T

struct MissingRow{T} <: Tables.AbstractRow
    names::Vector{Symbol}
    x::T
end

getmiss(x, nm) = haskey(x, nm) ? miss(getproperty(x, nm)) : missing
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
struct ObjectTable{T}
    x::T
end

StructTypes.StructType(::Type{<:ObjectTable}) = StructTypes.DictType()
Base.pairs(x::ObjectTable) = zip(Tables.columnnames(x.x), x.x)

struct ArrayTable{T}
    x::T
end

StructTypes.StructType(::Type{<:ArrayTable}) = StructTypes.ArrayType()

struct ArrayRow{T}
    x::T
end

StructTypes.StructType(::Type{<:ArrayRow}) = StructTypes.DictType()
Base.pairs(x::ArrayRow) = ((nm, Tables.getcolumn(x.x, nm)) for nm in Tables.columnnames(x.x))

Base.IteratorSize(::Type{ArrayTable{T}}) where {T} = IteratorSize(T)
Base.length(x::ArrayTable) = length(x.x)

function Base.iterate(x::ArrayTable, st=())
    state = iterate(x.x, st...)
    state === nothing && return nothing
    return ArrayRow(state[1]), (state[2],)
end

objecttable(table) = JSON3.write(ObjectTable(Tables.Columns(Tables.columns(table))))
objecttable(io::IO, table) = JSON3.write(io, ObjectTable(Tables.Columns(Tables.columns(table))))
arraytable(table) = JSON3.write(ArrayTable(Tables.rows(table)))
arraytable(io::IO, table) = JSON3.write(io, ArrayTable(Tables.rows(table)))

end # module
