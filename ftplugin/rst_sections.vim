" reStructuredText sections plugin
" Language:     Python (ft=python)
" Maintainer:   Matthew Brett
" Version:      Vim 7 (may work with lower Vim versions, but not tested)
" URL:          http://github.com/mathew-brett/myvim
"
" I got the structure of this plugin from
" http://github.com/nvie/vim-rst-tables by Vincent Driessen
" <vincent@datafox.nl>, with thanks.

" Only do this when not done yet for this buffer
if exists("g:loaded_rst_sections_ftplugin")
    finish
endif
let loaded_rst_sections_ftplugin = 1

python << endpython

import vim

import sys
from os.path import dirname

# get the directory this script is in: the vim_bridge python module should be
# installed there.
our_pth = dirname(vim.eval('expand("<sfile>")'))
sys.path.insert(0, our_pth)

import re
import textwrap

from vim_bridge import bridged

SECTION_CHARS=r"!\"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"


def is_underline(line):
    if len(line) == 0:
        return False
    char0 = line[0]
    if not char0 in SECTION_CHARS:
        return False
    return line == char0 * len(line)


def line_under_over(buf, line_no):
    """ Return line number of text, underline and overline from `buf`

    Consider also the case where the suggested line number `line_no` in fact
    points to an underline or overline.  If the line at line_no looks like an
    underline, and the text in the line above does not, and is not blank, then
    assume we are on an underline.  Otherwise check the line below in similar
    criteria, if that passes we are on an overline.  In each case, move the
    estimated line number to the detected text line.

    Parameters
    ----------
    buf : sequence
        sequence of lines
    line_no : int
        line number in `buf` in which to look for text with underline and overline

    Returns
    -------
    line_no : int
        detected text line
    under_line : None or int
        detected underline line number (None if not detected)
    over_line : None or int
        detected overline line number (None if not detected)
    """
    line = buf[line_no]
    try:
        below = buf[line_no+1]
    except IndexError:
        below = None
    if is_underline(line):
        moved = False
        # Could be underline or overline; check for underline
        if not line_no == 0:
            above = buf[line_no-1]
            if len(above) > 0 and not is_underline(above):
                line_no -= 1
                below = line
                line = above
                moved = True
        if not moved: # check for overline
            # If below doesn't seem to be text, bail
            if below is None or len(below) == 0 or is_underline(below):
                return line_no, None, None
            try:
                below2 = buf[line_no+2]
            except IndexError: # at end of buffer
                # no matching underline
                return line_no, None, None
            if (not is_underline(below2) or line[0] != below2[0]):
                # no matching underline
                return line_no, None, None
            return line_no+1, line_no+2, line_no
    elif below is None or not is_underline(below):
        # Not on an underline, but below isn't an underline either
        return line_no, None, None
    if line_no == 0:
        return line_no, 1, None
    above = buf[line_no-1]
    if is_underline(above) and above[0] == below[0]:
        return line_no, line_no+1, line_no-1
    return line_no, line_no+1, None


# Transitions between sections.  From Sphinx python doc hierarchy.
STATE_SEQ = (
    ('#', True),
    ('*', True),
    ('=', False),
    ('-', False),
    ('^', False),
    ('"', False),
    ('#', True))
NEXT_STATES = dict([(None, STATE_SEQ[0])] + zip(STATE_SEQ[:-1], STATE_SEQ[1:]))
PREV_STATES = dict([(None, STATE_SEQ[0])] + zip(STATE_SEQ[1:], STATE_SEQ[:-1]))


def current_lines():
    row, col = vim.current.window.cursor
    buf = vim.current.buffer
    line_no, below_no, above_no = line_under_over(buf, row-1)
    return line_no, below_no, above_no, buf


def ul_from_lines(line_no, below_no, above_no, buf, char, above=False):
    """ Apply section format `char` above at `buf` `line_no`
    """
    line = buf[line_no]
    underline = char * len(line)
    if not below_no is None:
        buf[below_no] = underline
    else:
        below_no = line_no+1
        buf.append(underline, below_no)
    if not above_no is None:
        if above:
            buf[above_no] = underline
        else:
            del buf[above_no]
            below_no -= 1
    elif above: # no above underlining and need some
        buf.append(underline, line_no)
        return below_no + 1
    return below_no


def last_section(buf, line_no):
    """ Find previous section, return line number, char, above flag

    Parameters
    ----------
    buf : sequence
        sequence of strings
    line_no : int
        element in sequence in which to start back search

    Returns
    -------
    txt_line_no : None or int
        line number of last section text, or None if none found
    char : None or str
        Character of section underline / overline or None of none found
    above_flag : None or bool
        True if there is an overline, false if not, None if no section found
    """
    curr_no = line_no
    while curr_no > 0: # Need underline AND text to make section
        line = buf[curr_no]
        curr_no -= 1
        if len(line) == 0:
            continue
        if not is_underline(line):
            continue
        txt_line = buf[curr_no]
        if len(txt_line) == 0 or is_underline(txt_line):
            # could recurse in this case, but hey
            continue
        # We definitely have a section at this point.  Is it overlined?
        txt_line_no = curr_no
        char = line[0]
        if curr_no == 0:
            above = False
        else:
            over_line = buf[curr_no-1]
            above = is_underline(over_line) and over_line[0] == char
        return txt_line_no, char, above
    return None, None, None


def all_sections(buf):
    """ Find all sections in document given by `buf`

    Parameters
    ----------
    buf : sequence
        sequence of strings

    Returns
    -------
    section_defs : tuple
        tuple of length 3 tuples, each containing:

        * txt_line_no : None or int
            line number of last section text
        * char : None or str
            Character of section underline / overline
        * above_flag : None or bool
            True if there is an overline, false if not
    """
    curr_no = len(buf) - 1
    sections = []
    while True:
        (curr_no, char, above) = last_section(buf, curr_no)
        if curr_no is None:
            break
        sections.insert(0, (curr_no, char, above))
        curr_no -= 1 + int(above)
    return tuple(sections)


def section_levels(section_defs):
    """ Return levels corresponding to section definitions

    Parameters
    ----------
    section_defs : tuple
        length S tuple of length 3 tuples, each containing:

        * txt_line_no : None or int
            line number of last section text
        * char : None or str
            Character of section underline / overline
        * above_flag : None or bool
            True if there is an overline, false if not

        Must be sorted in ascending order of ``txt_line_no``

    Returns
    -------
    levels : tuple
        length S tuple of ints, giving level of sections starting from 0 for
        top level
    """
    if len(section_defs) == 0:
        return ()
    if sorted(section_defs, key = lambda x : x[0]) != list(section_defs):
        raise ValueError('section_defs must be in line number order')
    level = -1 # will go up to 0 in first iteration through loop
    levels_d = {}
    levels = []
    for line_no, char, flag in section_defs:
        sect_id = (char, flag)
        if not sect_id in levels_d:
            # Must be down one
            level += 1
            levels_d[sect_id] = level
        else:
            new_level = levels_d[sect_id]
            # Can't go down more than one level
            if new_level > level + 1:
                raise ValueError("Inconsistent level at line %d" %
                                 (line_no + 1,))
            level = new_level
        levels.append(level)
    return tuple(levels)


def change_section(buf, line_no, from_above, to_char, to_above):
    """ Change section in `buf` at `line_no` to (`to_char`, `to_above`)

    Parameters
    ----------
    buf : buffer-like object
        such as a list of strings
    line_no : int
        index of string containing text of section heading

    """
    line_len = len(buf[line_no].rstrip())
    rule = to_char * line_len
    if to_above:
        if from_above:
            buf[line_no -1] = rule
        else:
            buf[line_no:line_no] = [rule] # no insert for buffer objects
            line_no += 1
    elif from_above: # not to_above
        del buf[line_no-1]
        line_no -= 1
    buf[line_no + 1] = rule
    return line_no


def to_standard_sections(buf, curr_line=0):
    """ Make sections correspond to standard section sequence

    Parameters
    ----------
    buf : buffer-like object

    Returns
    -------
    None

    Raises
    ------
    ValueError - if level beyond standard def range
    """
    sections = all_sections(buf)
    levels = section_levels(sections)
    max_level = len(STATE_SEQ) - 1
    cumulative_offset = 0
    for section, level in zip(sections, levels):
        if level > max_level:
            raise ValueError('Levels too deep for standard')
        line_no, char, above = section
        line_no += cumulative_offset
        to_char, to_above = STATE_SEQ[level]
        new_line = change_section(buf, line_no, above, to_char, to_above)
        line_offset = new_line - line_no
        if curr_line >= line_no:
            curr_line += line_offset
        cumulative_offset += line_offset
    return curr_line


def add_underline(char, above=False):
    line_no, below_no, above_no, buf = current_lines()
    curr_line = ul_from_lines(line_no, below_no, above_no, buf, char, above)
    vim.current.window.cursor = (curr_line+1, 0)


def section_cycle(cyc_func):
    """ Cycle section headings using section selector `cyc_func`

    Routine selects good new section heading type and inserts it into the
    buffer at the current location, moving the cursor to the underline for the
    section.

    Parameters
    ----------
    cyc_func : callable
        Callable returns section definition of form (char, overline_flag),
        where ``overline_flag`` is a bool specifying whether this section type
        has an overline or not.  Input to ``cyc_func`` is the current section
        definition, of the same form, or None, meaning we are not currently on
        a section, in which case `cyc_func` should return a good section to
        use.
    """
    line_no, below_no, above_no, buf = current_lines()
    if below_no is None:
        # In case of no current underline, use last, or first in sequence if
        # no previous section found
        _, char, above = last_section(buf, line_no-1)
        if char is None:
            char, above = cyc_func(None)
    else: # There is a current underline, cycle it
        current_state = (buf[below_no][0], not above_no is None)
        try:
            char, above = cyc_func(current_state)
        except KeyError:
            return
    curr_line = ul_from_lines(line_no, below_no, above_no, buf, char, above)
    vim.current.window.cursor = (curr_line+1, 0)


@bridged
def rst_section_reformat():
    line_no, below_no, above_no, buf = current_lines()
    if below_no is None:
        return
    above = not above_no is None
    char = buf[below_no][0]
    curr_line = ul_from_lines(line_no, below_no, above_no, buf, char, above)
    vim.current.window.cursor = (curr_line+1, 0)


@bridged
def rst_section_down_cycle():
    section_cycle(lambda x : NEXT_STATES[x])


@bridged
def rst_section_up_cycle():
    section_cycle(lambda x : PREV_STATES[x])


@bridged
def rst_section_standardize():
    curr_line, col = vim.current.window.cursor
    curr_line -= 1
    new_line = to_standard_sections(vim.current.buffer, curr_line)
    vim.current.window.cursor = (new_line + 1, col)


endpython

" Add mappings, unless the user didn't want this.
" The default mapping is registered, unless the user remapped it already.
if !exists("no_plugin_maps") && !exists("no_rst_sections_maps")
    if !hasmapto('RstSectionDownCycle(')
        noremap <silent> <leader><leader>d :call RstSectionDownCycle()<CR>
    endif
    if !hasmapto('RstSectionUpCycle(')
        noremap <silent> <leader><leader>u :call RstSectionUpCycle()<CR>
    endif
    if !hasmapto('RstSectionReformat(')
        noremap <silent> <leader><leader>r :call RstSectionReformat()<CR>
    endif
    if !hasmapto('RstSectionStandardize(')
        noremap <silent> <leader><leader>p :call RstSectionStandardize()<CR>
    endif
endif
