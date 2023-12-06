export def flip [x, ...a] { do $x $in $a }

export def tap [pred act] {
    let o = $in
    if (do $pred $o) {
        do $act $o
    } else {
        $o
    }
}

export def not-empty [] {
    not ($in | is-empty)
}

export def not-in [m] {
    not ($m in $in)
}

export def record-to-struct [$k $v] {
    $in | transpose $k $v | get 0
}

export def is-blank [txt] {
    ($txt | str replace -ra '\s' '') == ''
}

export def unindent [] {
    let txt = $in | lines
    let ib = if (is-blank $txt.0) { 1 } else { 0 }
    let ie = if (is-blank ($txt | last)) { -2 } else { -1 }
    let txt = $txt | range $ib..$ie
    let indent = $txt.0 | parse --regex '^(?P<indent>\s*)' | get indent.0 | str length
    $txt
    | each {|s| $s | str substring $indent.. }
    | str join (char newline)
}

export def cmd-with-args [tmpl] {
    {|args| do $tmpl ($args | str join ' ') | unindent }
}

export def 'str repeat' [n] {
    let o = $in
    mut a = ''
    if $n < 1 { return '' }
    for _ in 1..$n {
        $a = $"($a)($o)"
    }
    $a
}

export def mkact [action context body] {
    { action: $action, context: $context } | merge $body
}

export def log [title=''] {
    let o = $in
    print $"<<<<<< ($title) >>>>>>"
    print ($o | to yaml)
    print $">>>>>> ($title) <<<<<<"
    print $"(char newline)"
    $o
}

# export def 'bits check' [bit] {
#     ( $in | bits and  (1 | bits shl $bit) ) > 0
# }

export def deduplicate [getter] {
    let list = $in
    mut ex = []
    mut rt = []
    for i in $list {
        let n = do $getter $i
        if not ($n in $ex) {
            $ex ++= $n
            $rt ++= $i
        }
    }
    $rt
}

export def is-record [] {
    ($in | describe -d).type == 'record'
}

export def resolve-filename [name version] {
    $in
    | str replace -a '%v' $version
    | str replace -a '%n' $name
    | str replace -a '%t' (date now | format date '%Y%m%d')
}
