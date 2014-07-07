using TermWin

Profile.init( 1000000, 0.02 )
@profile tshow( TermWin, title="TermWin" )
Profile.print()
