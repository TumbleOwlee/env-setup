function __colored_cat
    set -l argc (count $argv)
    set -l color 33

    if test $argc -gt 0
        if test "$argv[1]" = "--version"
            /usr/bin/cat --version
            exit 0
        end

        # Get maximal length
        set -l length 80
        for var in $argv
            set -l len (string length $var)
            if test $len -gt $length
                set length $len
                echo "$length"
            end
        end

        set -l sep (head -c $length < /dev/zero | tr '\0' '-' | sed 's/-/─/g')

        echo "" >&2
        for var in (seq 1 $argc)
            set -l len (string length $argv[$var])
            set -l fill_len (math $length - $len)
            set -l fill (head -c $fill_len < /dev/zero | tr '\0' ' ')

            echo -e "  \033["$color"m┌────────────$sep─┐\033[0m" >&2
            echo -e "  \033["$color"m│ Filename : $argv[$var]$fill │\033[0m" >&2
            echo -e "  \033["$color"m└────────────$sep─┘\033[0m" >&2
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
