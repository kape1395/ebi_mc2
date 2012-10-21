#
#  Supervisor for the solver. Almost supervisor :)
#
#  Param: data -- Simulation data directory.
#  Param: cleanup -- Cleanup program taking data dir as a first argument.
#  Param: step -- Number of seconds every which the cleanup tasks should be run.
#
BEGIN{
    lastTime = systime()
}
/processNextStep/{
    thisTime = systime()
    if (thisTime > lastTime + step) {
        lastTime = thisTime
        printf("%s, cleanup executed, rc=%i\n", $0, system(cleanup " " data))
    }
    next
}
{
    print
}
END{
    printf("Final cleanup executed, rc=%i\n", system(cleanup " " data))
}
