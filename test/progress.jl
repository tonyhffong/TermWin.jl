using TermWin

trun( ()->begin
    n = 2000
    for i=1:n
        TermWin.progressUpdate( i/n )
        TermWin.progressMessage( ( @sprintf( "%d/%d ", i, n ) ) * strftime( "%H:%M:%S", time() ) )
        if mod(i,10)==0
            sleep(50.0/n)
        end
    end
    n
end )
