' =============================================================================
' SHEEPFALL for Roku - entry point. Everything lives in App.brs so that the
' automated smoke test can start the same app with a scripted remote.
' =============================================================================

sub Main(args as dynamic)
    AppMain(args, invalid)
end sub
