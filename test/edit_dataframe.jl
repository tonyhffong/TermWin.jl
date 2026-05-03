using TermWin, DataFrames, Dates
#An example to make an editable table

#It is mandatory to call allowmissing first if any of the column could have missing values
df = allowmissing( DataFrame(name=["Alice","Bob","Charlie"], score=[3.14,2.71,1.41],
                 grade=["A","B","A"], hired=[Date(2024,1,1),Date(2024,2,1),Date(2024,3,1)],
                 fired=[missing, missing, Date( 2026,1,1) ]
                ) )
# Argument order for TwEditTableCol:
# Name as the symbol, Header string, width, editable, DataType, enumvalues, missingok
# DataType: no need to do Union with Missing
cols = [TwEditTableCol(:name,"Name",14,true,String,nothing, false),
        TwEditTableCol(:score,"Score",10,true,Float64,nothing, true),
        TwEditTableCol(:grade,"Grade",8,true,String,["A","B","C"], true),
        TwEditTableCol(:hired,"Hired",12,false,Date,nothing, false),
        TwEditTableCol(:fired,"Fired",12,true,Date,nothing, true)
       ]
tshow(df, cols; title="Edit Records")
