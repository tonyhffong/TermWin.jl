using TermWin, DataFrames, Dates
df = DataFrame(name=["Alice","Bob","Charlie"], score=[3.14,2.71,1.41],
                 grade=["A","B","A"], hired=[Date(2024,1,1),Date(2024,2,1),Date(2024,3,1)])
cols = [TwEditTableCol(:name,"Name",14,true,String,nothing),
        TwEditTableCol(:score,"Score",10,true,Float64,nothing),
        TwEditTableCol(:grade,"Grade",8,true,String,["A","B","C"]),
        TwEditTableCol(:hired,"Hired",12,false,Date,nothing)]
tshow(df, cols; title="Edit Records")
