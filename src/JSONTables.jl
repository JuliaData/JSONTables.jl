module JSONTables

using StructTypes, JSON3, Tables

export jsontable, arraytable, objecttable

# read

struct Table{columnar, T}
    source::T
end

function jsontable(source)
    x = !(source isa JSON3.Object || source isa JSON3.Array) ? JSON3.read(source) : source
    columnar = x isa JSON3.Object && first(x)[2] isa AbstractArray
    columnar || x isa JSON3.Array || throw(ArgumentError("input json source is not a table"))
    return Table{columnar, typeof(x)}(x)
end

function jsontable(x::JSON3.Object)
    columnar = first(x)[2] isa AbstractArray
    columnar || x isa JSON3.Array || throw(ArgumentError("input json source is not a table"))
    return Table{columnar, typeof(x)}(x)
end

Tables.istable(::Type{<:Table}) = true

# columnar source
Tables.columnaccess(::Type{Table{true, T}}) where {T} = true
Tables.columns(x::Table{true}) = x

miss(x) = ifelse(x === nothing, missing, x)
struct MissingVector{T} <: AbstractVector{T}
    x::T
end
Base.IndexStyle(::Type{<:MissingVector}) = Base.IndexLinear()
# Base.length(x::MissingVector) = length(x.x)
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
    x::T
end

Tables.columnnames(x::MissingRow) = propertynames(getfield(x, :x))
Tables.getcolumn(x::MissingRow, nm::Symbol) = miss(getproperty(getfield(x, :x), nm))
Tables.getcolumn(x::MissingRow, i::Int) = getproperty(x, propertynames(x)[i])

@inline function Base.iterate(x::Table{false})
    st = iterate(x.source)
    st === nothing && return nothing
    val, state = st
    return MissingRow(val), state
end

@inline function Base.iterate(x::Table{false}, st)
    st = iterate(x.source, st)
    st === nothing && return nothing
    val, state = st
    return MissingRow(val), state
end

# write
struct ObjectTable{T}
    x::T
end

StructTypes.StructType(::Type{<:ObjectTable}) = StructTypes.DictType()
Base.pairs(x::ObjectTable) = zip(Tables.columnnames(x.x), Tables.Columns(x.x))

struct ArrayTable{T}
    x::T
end

StructTypes.StructType(::Type{<:ArrayTable}) = StructTypes.ArrayType()

struct ArrayRow{T}
    x::T
end

StructTypes.StructType(::Type{<:ArrayRow}) = StructTypes.DictType()
Base.pairs(x::ArrayRow) = zip(Tables.columnnames(x.x), Tables.Columns(x.x))

Base.IteratorSize(::Type{ArrayTable{T}}) where {T} = IteratorSize(T)
Base.length(x::ArrayTable) = length(x.x)

function Base.iterate(x::ArrayTable)
    state = iterate(x.x)
    state === nothing && return nothing
    return ArrayRow(state[1]), state[2]
end

function Base.iterate(x::ArrayTable, st)
    state = iterate(x.x, st)
    state === nothing && return nothing
    return ArrayRow(state[1]), state[2]
end

objecttable(table) = JSON3.write(ObjectTable(Tables.columns(table)))
objecttable(io::IO, table) = JSON3.write(io, ObjectTable(Tables.columns(table)))
arraytable(table) = JSON3.write(ArrayTable(Tables.rows(table)))
arraytable(io::IO, table) = JSON3.write(io, ArrayTable(Tables.rows(table)))

end # module
