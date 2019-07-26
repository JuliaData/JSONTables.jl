using Test, JSONTables, Tables, JSON3

@testset "JSONTables" begin

cjson = replace(replace("""{
"a": [1,2,3],
"b": [4.1, 5.2, 6.3],
"c": ["7", "8", "9"]
}""", " "=>""), "\n"=>"")

rjson = replace(replace("""[
{"a": 1, "b": 4.1, "c": "7"},
{"a": 2, "b": 5.2, "c": "8"},
{"a": 3, "b": 6.3, "c": "9"}
]""", " "=>""), "\n"=>"")

ctable = (a=[1,2,3], b=[4.1, 5.2, 6.3], c=["7", "8", "9"])
rtable = Tables.rowtable(ctable)

cjtable = JSONTables.jsontable(cjson)
rjtable = JSONTables.jsontable(rjson)

@test Tables.istable(typeof(cjtable))
@test Tables.istable(typeof(rjtable))

@test Tables.columnaccess(typeof(cjtable))
@test !Tables.rowaccess(typeof(cjtable))
@test Tables.columns(cjtable) === cjtable
@test propertynames(cjtable) == (:a, :b, :c)
@test getproperty(cjtable, :a) == [1, 2, 3]

@test !Tables.columnaccess(typeof(rjtable))
@test Tables.rowaccess(typeof(rjtable))
@test Tables.rows(rjtable) === rjtable
@test Base.IteratorSize(typeof(rjtable)) == Base.HasLength()
@test length(rjtable) == 3
@test Base.IteratorEltype(typeof(rjtable)) == Base.HasEltype()
@test eltype(rjtable) == Any

@test Tables.columntable(cjtable) == ctable
@test Tables.columntable(rjtable) == ctable
@test Tables.rowtable(cjtable) == rtable
@test Tables.rowtable(rjtable) == rtable

@test JSONTables.objecttable(ctable) == cjson
@test JSONTables.objecttable(rtable) == cjson
@test JSONTables.arraytable(ctable) == rjson
@test JSONTables.arraytable(rtable) == rjson

io = IOBuffer()
JSONTables.objecttable(io, ctable)
@test String(take!(io)) == cjson

JSONTables.arraytable(io, rtable)
@test String(take!(io)) == rjson

end
