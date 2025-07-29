# Easytag - simple file-objects tagging tool/script

## About

This is a simple command line tool to tag files, directories and to search
them by these tags. It supports:

- output in different formats
- output in "clickable" format (console URL) allowing to open tagged file, directory
- output in "executable" format (shell command) allowing to open, jump to tagged file, directory,
  directory of the file
- output in Emacs ORG-MODE allowing to see tagged files, directories in a document-like
  format with ability to jump to tagged file, directory
- output in GREP-like format
- color output (optional)
- shell (Bash) autocomplete
- very simple structure of tags repository allowing easy manual modification of it

The tool (easytags) is written in Common Lisp and it is crossplatform, but the author mostly
tested it on Linux.

## Examples of usage

```
# Tag a file or a directory:
<TOOL> tag some_file tag1 tag2 tag3

# List all tagged objects:
<TOOL> tagged

# List by tag's regexp:
<TOOL> tagged 'tag[1-9]+'

# List by specific tag's regexp:
<TOOL> tagged 'user!tag[1-9]+'

# List by tag's regexp and tag-file's regexp:
<TOOL> tagged 'tag[1-9]+' 'somefile[0-9]+'

# List with standard report:
<TOOL> agged mytag -o REPORT

# List with grep-like report:
<TOOL> tagged mytag -o GREP

# List with grep-like report to Vim:
<TOOL> tagged mytag -o GREP|vim -

# List with Emacs org-mode report in ZSH:
emacs =(<TOOL> tagged mytag -o GREP)

# List with X console report supporting URL click:
<TOOL> tagged mytag -o XCONS

# List with cd-commands report (copy-paste, execute):
<TOOL> tagged mytag -o CD

# List suppressing color:
<TOOL> tagged mytag -c 0

# List forcing color:
<TOOL> tagged mytag -c 1

# List all known tags:
<TOOL> tags

# List all user tags:
<TOOL> tags -u

# List all tag directories:
<TOOL> tags -t

# Inject autocomplete code in BASH shell:
source <(<TOOL> autocomplete -s BASH)
```

## Storage

Typically the storage is `.tags` directory in the user's home directory.
But it can be changed with an environment variable `EASYTAG_HOME`.

The structure of the storage looks similarly to:

```
/home/<USER>/.tags
├── a-1C54DF84F7F8FD78
│   ├── link -> /home/<USER>/proj/dir1/a.py
│   └── tags
├── groovy-language-server-3816B49D3C72DD87
│   ├── link -> /home/<USER>/proj/dir2/groovy-language-server/
│   └── tags
└── zz-357E10D1499BFB13
    ├── link -> /home/<USER>/proj/dir3/zz.xml
    └── tags
         :
         `........CONTENT..of..tags..file.........
          :                                      :
          : src!/home/<USER>/proj/dir3/zz.xml    :
          : user!tag3                            :
          :                                      :
          :......................................:
```

where we see that file `zz.xml` from `proj/dir3/` is tagged by `tag3` tag (which
was entered by a user, so it's in `user` namespace). The `tag`-file is just usual
text file and can be modified manually.

To find it and jump/open it or its directory, you can use, for example:

```
$ <TOOL> tagged tag3 -o XCONS
[Tags] file:///home/<USER>/.tags/zz-357E10D1499BFB13/tags
[ Src] file:///home/<USER>/proj/dir3/zz.xml
[ Dir] file:///home/<USER>/proj/dir3/
user!tag3
```

then click on the link by the mouse and that's it!

If you want to change the current Shell directory to the directory of the tagged
object (of `xx.zml` file), do:

```
`<TOOL> tagged tag3 -o CD`
```

and so on.
