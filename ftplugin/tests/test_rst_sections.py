""" Tests for rst-sections

It's a bit nasty, but we pull out the python from the vim file, and test that

Run with nosetests
"""

import sys
from os.path import dirname, join as pjoin, split as psplit
import re
import imp
from itertools import cycle

from nose.tools import assert_true, assert_false, assert_equal, assert_raises


THIS_DIR = dirname(__file__)
CODE_DIR, _ = psplit(THIS_DIR)
VIM_FILE = pjoin(CODE_DIR, 'rst_sections.vim')

# Pull python code out of vim file
_all_code = open(VIM_FILE).read()
_match = re.search(r"python << endpython(.*)endpython", _all_code, flags=re.DOTALL)
if not _match:
    raise RuntimeError('Could not find python code in file %s' % VIM_FILE)
PY_CODE = _match.groups()[0]

# Make something that looks like the vim module
assert "vim" not in sys.modules
sys.path.insert(0, THIS_DIR)
import fakevim
sys.modules["vim"] = fakevim
# And something that looks like the vim_bridge module.  This only needs to give
# a null decorator.
vim_bridge = imp.new_module('vim_bridge')
vim_bridge.bridged = lambda x : x
sys.modules['vim_bridge'] = vim_bridge

exec(PY_CODE)

def test_is_underline():
    for char in SECTION_CHARS:
        for n in range(1,4):
            line = char * n
            assert_true(is_underline(line))
    assert_false(is_underline(''))
    assert_false(is_underline('aa'))
    assert_false(is_underline('+++=+'))


def test_line_is_underline():
    assert_equal(line_under_over([''], 0), (0, None, None))
    assert_equal(line_under_over(['Text'], 0), (0, None, None))
    assert_equal(line_under_over(['Text', 'Text2'], 0), (0, None, None))
    assert_equal(line_under_over(['Text', '===='], 0), (0, 1, None))
    # Do we find the text line when we pass the underline?
    assert_equal(line_under_over(['Text', '===='], 1), (0, 1, None))
    # Do we find the overline?
    assert_equal(line_under_over(['====', 'Text', '===='], 1), (1, 2, 0))
    # When we pass the under or overline?
    assert_equal(line_under_over(['====', 'Text', '===='], 2), (1, 2, 0))
    assert_equal(line_under_over(['====', 'Text', '===='], 0), (1, 2, 0))
    # Do we reject the underline if it's too short? No
    assert_equal(line_under_over(['Text', '==='], 0), (0, 1, None))
    assert_equal(line_under_over(['Text', '==='], 1), (0, 1, None))
    # Do we reject the overline if it's too short?
    assert_equal(line_under_over(['===', 'Text', '===='], 1), (1, 2, 0))
    assert_equal(line_under_over(['===', 'Text', '===='], 2), (1, 2, 0))
    assert_equal(line_under_over(['===', 'Text', '===='], 0), (1, 2, 0))


def test_prev_section():
    try0 = """
One

Two

Three
+++++

Four
""".split('\n')
    assert_equal(last_section(try0, len(try0)-1), (5, '+', False))
    try0[4] = '+++++'
    assert_equal(last_section(try0, len(try0)-1), (5, '+', True))
    try0[6] = ''
    assert_equal(last_section(try0, len(try0)-1), (3, '+', False))
    try0[4] = '^'
    assert_equal(last_section(try0, len(try0)-1), (3, '^', False))
    try0[4] = ''
    assert_equal(last_section(try0, len(try0)-1), (None, None, None))
    try0[0] = '-------'
    assert_equal(last_section(try0, len(try0)-1), (None, None, None))
    try0[2] = '-------'
    assert_equal(last_section(try0, len(try0)-1), (1, '-', True))


BAD_LEVELS_BUF = """

Level 0
~~~~~~~

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

Level 2
++

One two three
""".split('\n')


def test_reformat_sections():
    # Test finding all sections
    exp_levels = ((2, '~', False),
                  (8, '#', True),
                  (15, '+', False),
                  (21, '=', True),
                  (26, '#', True),
                  (31, '+', False))
    assert_equal(all_sections(BAD_LEVELS_BUF), exp_levels)


def test_section_levels():
    # Must be sorted
    sections = ((8, '~', False),
                (2, '#', True),
                (15, '+', False))
    assert_raises(ValueError, section_levels, sections)
    # Length 0 return empty tuple
    assert_equal(section_levels(()), ())
    # Test algorithm to find levels for sections
    sections = ((2, '~', False),
                (8, '#', True),
                (15, '+', False),
                (21, '=', True),
                (26, '#', True),
                (31, '+', False))
    assert_equal(section_levels(sections),
                 (0, 1, 2, 3, 1, 2))
    # Must be consistent
    sections = ((2, '~', False),
                (8, '#', True),
                (15, '+', False),
                (21, '=', True),
                (26, '#', True),
                (31, '=', True))
    # Title level inconsistent
    assert_raises(ValueError, section_levels, sections)


def test_change_section():
    # Test replacement of section
    buf = ['Head', '--', '']
    assert_equal(change_section(buf, 0, False, '-', True), 1)
    assert_equal(buf, ['----', 'Head', '----', ''])
    assert_equal(change_section(buf, 1, True, '~', True), 1)
    assert_equal(buf, ['~~~~', 'Head', '~~~~', ''])
    assert_equal(change_section(buf, 1, True, '=', False), 0)
    assert_equal(buf, ['Head', '====', ''])
    buf = ['', 'More text', ''] + buf
    assert_equal(change_section(buf, 3, False, '*', False), 3)
    assert_equal(buf, ['', 'More text', '', 'Head', '****', ''])
    buf = ['  Head', '--', '']
    assert_equal(change_section(buf, 0, False, '-', True), 1)
    assert_equal(buf, ['------', '  Head', '------', ''])


GOOD_LEVELS_BUF = """

#######
Level 0
#######

Some text

*******
Level 1
*******

More text

Some lines

Level 2
=======

Keep with this text

Level 3
-------
Tiring of text

*******
Level 1
*******

Thinking of numbers

Level 2
=======

One two three
""".split('\n')

def make_levels(sect_defs):
    buf = []
    for i, sect_def in enumerate(sect_defs):
        char, above = sect_def
        head = 'Level %02d' % i
        rule = char * len(head)
        if above:
            buf.append(rule)
        buf.append(head)
        buf.append(rule)
        buf.append('More text')
    return buf


def test_to_standard_sections():
    # Test going from non-standard to standard sections
    levels_buf = BAD_LEVELS_BUF[:]
    to_standard_sections(levels_buf)
    assert_equal(levels_buf, GOOD_LEVELS_BUF)
    # Go all the way down the levels
    bad_sect_defs = zip(SECTION_CHARS[:7], cycle([True]))
    bad_buf = make_levels(bad_sect_defs)
    good_buf = make_levels(STATE_SEQ)
    to_standard_sections(bad_buf)
    assert_equal(bad_buf, good_buf)
    # Go too far down nesting
    bad_sect_defs = zip(SECTION_CHARS[:8], cycle([True]))
    bad_buf = make_levels(bad_sect_defs)
    assert_raises(ValueError, to_standard_sections, bad_buf)
