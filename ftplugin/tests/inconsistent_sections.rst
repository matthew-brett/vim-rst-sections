These sections will raise an error with::

    call RstSectionStandardize()

because, at around line 37, the sections try to drop two levels, which is not
allowed by ReST.

Level 0
--

Some text

#######
Level 1
#######

More text

Some lines

Level 2
+++++++

Keep with this text

==
Level 3
=======
Tiring of text

##
Level 1
#######

Thinking of numbers
==
Level 2
==

One two three
