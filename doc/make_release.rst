################
Making a release
################

******
Checks
******

Run the Python tests with::

    cd ftplugin
    nosetests tests

For each document ``ftplugin/tests/*.rst``

* open in vim
* run ``call RstSectionStandardize()``

*******
Release
*******

Set the version name in ``rst_sections.vim``.

Make commit.

Add annotated tag of form ``git tag -a v0.1.0``

Make archive with something like::

    git archive --format=zip --prefix=vim-rst-sections-0.1/ -o ../vim-rst-sections-0.1.zip v0.1.0

Check archive with something like::

    cd ~/tmp
    mkdir test
    cd test
    unzip ~/dev_trees/vim-rst-sections-0.1.zip

Upload to vim scripts page.

Copy contents of README into description / install instructions
