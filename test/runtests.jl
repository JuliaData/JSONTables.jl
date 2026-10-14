using Test, JSONTables, Tables, JSON3

@testset "JSONTables" begin

cjson = replace(replace("""{
"a": [1,2,3],
"b": [4.1, null, 6.3],
"c": ["7", "8", null]
}""", " "=>""), "\n"=>"")

rjson = replace(replace("""[
{"a": 1, "b": 4.1, "c": "7"},
{"a": 2, "b": null, "c": "8"},
{"a": 3, "b": 6.3, "c": null}
]""", " "=>""), "\n"=>"")

ctable = (a=[1,2,3], b=[4.1, missing, 6.3], c=["7", "8", missing])
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

@test isequal(Tables.columntable(cjtable), ctable)
@test isequal(Tables.columntable(rjtable), ctable)
@test isequal(Tables.rowtable(cjtable), rtable)
@test isequal(Tables.rowtable(rjtable), rtable)

@test JSONTables.objecttable(ctable) == cjson
@test JSONTables.objecttable(rtable) == cjson
@test JSONTables.arraytable(ctable) == rjson
@test JSONTables.arraytable(rtable) == rjson

io = IOBuffer()
JSONTables.objecttable(io, ctable)
@test String(take!(io)) == cjson

JSONTables.arraytable(io, rtable)
@test String(take!(io)) == rjson

# #7
text = """{
        "color_scheme": "Packages/Color Scheme - Default/Mariana.sublime-color-scheme",
        "dictionary": "Packages/Language - English/en_US.dic",
        "draw_white_space": "all",
        "font_face": "monospace 821",
        "font_size": "10",
        "theme": "Adaptive.sublime-theme"
}"""
@test_throws ArgumentError JSONTables.jsontable(text)

nonhomogenous = """
[
    {"a": 1, "b": 2, "c": 3},
    {"b": 4, "c": null, "d": 5},
    {"a": 6, "d": 7},
    {"a": 8, "b": 9, "c": 10, "d": null},
    {"d": 11, "c": 10, "b": 9, "a": 8}
]
"""

jt = JSONTables.jsontable(nonhomogenous)
@test Tables.schema(jt).names == (:a, :b, :c, :d)
ct = Tables.columntable(jt)
@test isequal(ct.a, [1, missing, 6, 8, 8])
@test isequal(ct.d, [missing, 5, 7, missing, 11])

new_field_in_last_row = """
[
    {"a": 1, "b": 2},
    {"b": 4, "c": 8}
]
"""

jt = JSONTables.jsontable(new_field_in_last_row)
ct = Tables.columntable(jt)
@test isequal(ct.c, [missing, 8])

@testset "row inputs and empty initial rows" begin
    text = "[{\"a\":1,\"b\":2},{\"a\":3,\"b\":4}]"
    parsed = JSON3.read(text)
    concrete = typeof(parsed[1])[parsed...]
    for input in (text, codeunits(text), IOBuffer(text), parsed,
                  JSON3.Object[parsed...], concrete, view(concrete, 1:2))
        @test Tables.columntable(JSONTables.jsontable(input)) == (a=[1, 3], b=[2, 4])
    end
    for text in ("[]", "[1,2]", "[{},1]", "[null]")
        @test_throws ArgumentError JSONTables.jsontable(text)
    end
    for (text, a) in (("[{},{\"a\":1}]", [missing, 1]), ("[{},{},{\"a\":null}]", [missing, missing, missing]))
        table = JSONTables.jsontable(text)
        @test Missing <: Tables.schema(table).types[1]
        @test isequal(Tables.columntable(table).a, a)
    end
end

@testset "empty and null columns" begin
    for text in ("{\"a\":[],\"b\":[1]}", "{\"a\":[1],\"b\":[]}", "{\"a\":[1],\"b\":[2,3]}")
        @test_throws ArgumentError JSONTables.jsontable(text)
    end
    @test isequal(Tables.columntable(JSONTables.jsontable("{\"a\":[],\"b\":[]}")), (a=Any[], b=Any[]))
    table = JSONTables.jsontable("{\"a\":[null,null]}")
    @test Tables.schema(table).types == (Missing,)
    @test isequal(Tables.columntable(table), (a=[missing, missing],))
end

@testset "column element types" begin
    for (text, expected) in (("{\"a\":[1,2]}", [1, 2]),
                             ("{\"a\":[1,null]}", [1, missing]),
                             ("{\"a\":[null]}", [missing]),
                             ("{\"a\":[]}", Any[]))
        table = JSONTables.jsontable(text)
        @test eltype(table.a) == Tables.schema(table).types[1]
        @test isequal(collect(table.a), expected)
    end
end

end
