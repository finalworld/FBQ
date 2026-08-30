package se.frasse.bonequest

/** Prevents the foreground UI and walking service from duplicating GPS/network work. */
object AppVisibility {
    @Volatile var isForeground:Boolean=false
        internal set
}
