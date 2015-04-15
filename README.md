Smartdelete is a UNIX utility which creates a pseudo-Recycle Bin for storing files without completely deleting them. 
Usage: smartdelete (args) file... The script supports a few arguments:

-d (default): "delete" all files in arguments.
-r: restore all files in arguments to current directory.
-o: restore all files in arguments to the original directory they were "deleted" from.
-c: clear the Recycle Bin, permanently deleting all files within.
-l: list all unique filenames within the recycle bin. 
