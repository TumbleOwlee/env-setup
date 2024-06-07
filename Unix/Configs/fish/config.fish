function __colored_cat
    set -l argc (count $argv)
    if test $argc -gt 0
        echo "" >&2
        for var in (seq 1 $argc)
            echo "  ================================================================================================" >&2
            echo "    Filename : $argv[$var]" >&2
            echo "  ================================================================================================" >&2
            echo "" >&2
            set -l lines (pygmentize -g -O style=gruvbox-dark $argv[$var] 2>/dev/null | /usr/bin/cat -n)
            for line in $lines
                set -l lineno (echo "$line" | cut -f1)
                set -l lineco (echo "$line" | cut -f2- | sed 's/\t/    /g')
                echo -n "$lineno | " >&2
                echo $lineco
            end
            echo "" >&2
        end
    end
end

alias ccat=(which cat)
alias cat=__colored_cat
