command! -range=% IkiwikiGitHubURItoTemplate <line1>,<line2>s,<\?https\?://github.com/\([^/]\+/[^/]\+/\(pull\|issues\)/\d\+\)>\?,[[!template id=github item="\1"]],g
