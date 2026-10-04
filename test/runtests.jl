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
    expected_columns = (a=[1, 3], b=[2, 4])
    expected_rows = Tables.rowtable(expected_columns)
    for input in (text, Vector{UInt8}(codeunits(text)), IOBuffer(text), parsed,
                  JSON3.Object[parsed...], concrete, view(concrete, 1:2))
        table = JSONTables.jsontable(input)
        @test Tables.schema(table).names == (:a, :b)
        @test Tables.columntable(table) == expected_columns
        @test Tables.rowtable(table) == expected_rows
    end
    for text in ("[]", "[1,2]", "[{},1]", "[null]")
        for input in (text, Vector{UInt8}(codeunits(text)), JSON3.read(text))
            @test_throws ArgumentError JSONTables.jsontable(input)
        end
    end
    for text in ("[{},{\"a\":1}]", "[{},{},{\"a\":1}]", "[{},{\"a\":null},{\"a\":1}]")
        parsed = JSON3.read(text)
        expected = [haskey(row, :a) && row.a !== nothing ? row.a : missing for row in parsed]
        for input in (text, parsed, JSON3.Object[parsed...])
            table = JSONTables.jsontable(input)
            @test Missing <: Tables.schema(table).types[1]
            @test isequal(Tables.columntable(table).a, expected)
            @test isequal(getproperty.(Tables.rowtable(table), :a), expected)
        end
    end
    table = JSONTables.jsontable("[{\"a\":1},{\"a\":2}]")
    @test Tables.schema(table).types[1] === typeof(JSON3.read("{\"a\":1}").a)
    table = JSONTables.jsontable("[{\"a\":1},{\"b\":2}]")
    @test isequal(Tables.columntable(table), (a=[1, missing], b=[missing, 2]))
    table = JSONTables.jsontable(JSON3.Object[])
    @test length(table) == 0
    @test Tables.schema(table).names == ()
    table = JSONTables.jsontable("[{\"a\":NaN}]"; allow_inf=true)
    @test isnan(Tables.columntable(table).a[1])
end

@testset "empty and null columns" begin
    for text in ("{\"a\":[],\"b\":[1]}", "{\"a\":[1],\"b\":[]}",
                 "{\"a\":[],\"b\":[],\"c\":[1]}",
                 "{\"a\":[1],\"b\":[2,3]}", "{\"a\":[1,2],\"b\":[3]}",
                 "{\"a\":[null],\"b\":[]}")
        @test_throws ArgumentError JSONTables.jsontable(text)
        @test_throws ArgumentError JSONTables.jsontable(JSON3.read(text))
    end
    for (text, expected) in (("{\"a\":[]}", (a=Any[],)),
                             ("{\"a\":[],\"b\":[]}", (a=Any[], b=Any[])),
                             ("{\"a\":[1,2],\"b\":[3,4]}", (a=[1,2], b=[3,4])),
                             ("{\"a\":[1,2],\"b\":[null,3]}", (a=[1,2], b=[missing,3])))
        table = JSONTables.jsontable(text)
        @test isequal(Tables.columntable(table), expected)
        @test isequal(Tables.rowtable(table), Tables.rowtable(expected))
    end
    @test Tables.schema(JSONTables.jsontable("{\"a\":[]}")).types == (Any,)
    @test Tables.schema(JSONTables.jsontable("{\"a\":[],\"b\":[]}")).types == (Any, Any)
    for (text, expected) in (("{\"a\":[null]}", (a=[missing],)),
                             ("{\"a\":[null,null]}", (a=[missing,missing],)))
        for source in (text, codeunits(text), IOBuffer(text), JSON3.read(text))
            table = JSONTables.jsontable(source)
            @test Tables.schema(table).types == (Missing,)
            @test isequal(Tables.columntable(table), expected)
            @test isequal(Tables.rowtable(table), Tables.rowtable(expected))
        end
    end
end

@testset "column element types" begin
    for (text, expected) in (("{\"a\":[1,2]}", [1,2]),
                             ("{\"a\":[1,null,2]}", [1,missing,2]),
                             ("{\"a\":[null,null]}", [missing,missing]),
                             ("{\"a\":[\"x\",\"y\"]}", ["x","y"]),
                             ("{\"a\":[]}", Any[]),
                             ("{\"a\":[{\"b\":1},{\"b\":2}]}", [Dict(:b=>1),Dict(:b=>2)]),
                             ("{\"a\":[[1,2],[3,4]]}", [[1,2],[3,4]]))
        table = JSONTables.jsontable(text)
        for column in (Tables.getcolumn(table, :a), Tables.getcolumn(table, 1), table.a)
            @test eltype(column) == Tables.schema(table).types[1]
            @test isequal(collect(column), expected)
            @test isequal(copy(column), expected)
        end
    end
end

end
