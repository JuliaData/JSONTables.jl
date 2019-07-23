# JSONTables.jl

A package that provides a JSON integration with the [Tables.jl](https://github.com/JuliaData/Tables.jl) interface, that is, it provides the `jsontable` function as a way to treat a JSON object of arrays, or a JSON array of objects, as a Tables.jl-compatible source. This allows, among other things, loading JSON "tabular" data into a DataFrame, or a JuliaDB table, or written out directly as a csv file.

JSONTables.jl also provides two "write" functions, `objecttable` and `arraytable`, for taking any Tables.jl-comptabile source (e.g. DataFrame, ODBC.Query, etc.) and writing the table out either as a JSON object of arrays, or array of objects, respectively.

So in short:
```julia
# treat a json object of arrays or array of objects as a "table"
jtable = jsontable(json_source)

# turn json table into DataFrame
df = DataFrame(jtable)

# turn DataFrame back into json object of arrays
objecttable(df)

# turn DataFrame back into json array of objects
arraytable(df)
```
