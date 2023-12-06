def calc-dep-require [pkgs comp] {
    let dep = if ($comp.require? | is-empty) { [] } else {
        $pkgs
        | where name in $comp.require
        | each {|y| calc-dep-require $pkgs $y}
        | flatten
    }
    $comp | append $dep
}

def calc-dep-use [pkgs comp] {
    let r = if ($comp.require? | not-empty) { $comp.require } else { [] }
    let r = $r | append (if ($comp.use? | not-empty) { $comp.use } else { [] })
    $comp
    | append (
        if ($r | is-empty) { [] } else {
            $pkgs
            | where name in $r
            | each {|y| calc-dep-use $pkgs $y}
            | flatten
        }
    )
}

export def sort [cs] {
    let o = $in
    let r = $o
        | where name in $cs
        | each {|y| calc-dep-require $o $y }
        | flatten
        | deduplicate {|y| $y.name }
    let u = $o
        | where name in $cs
        | each {|y| calc-dep-use $o $y }
        | flatten
        | deduplicate {|y| $y.name }
    {
        require: $r
        use: $u
    }
}

export def resolve [] {
    let o = $in
        | reduce -f {require: [], use: []} {|x, acc|
            mut acc = $acc
            for i in $x.require? {
                if ($i.include? | not-empty) {
                    $acc.require = ($acc.require | append $i.include)
                }
            }
            for i in $x.use? {
                if ($i.include? | not-empty) {
                    $acc.use = ($acc.use | append $i.include)
                }
            }
            $acc
        }
    let r = $o.require | deduplicate {|x| $x}
    let u = $o.use | deduplicate {|x| $x}
    {
        require: $r
        use: ($u | filter {|x| not ($x in $r) })
    }
}

export def resolve-def [defs require --os-type:string] {
    mut os = []
    mut recipe = []
    mut pip = []
    mut npm = []
    mut cargo = []
    mut stack = []
    mut go = []
    for p in $require {
        if ($p | is-record) {
            for i in ($p | transpose k v) {
                match $i.k {
                    'pip' => { $pip ++= $i.v }
                    'npm' => { $npm ++= $i.v }
                    'cargo' => { $cargo ++= $i.v }
                    'stack' => { $stack ++= $i.v }
                    'go' => { $go ++= $i.v }
                }
                if $i.k == $os_type {
                    $os ++= $i.v
                }
            }
        } else if ($p in $defs) {
            $recipe ++= $p
        } else {
            $os ++= $p
        }
    }
    {
        os: $os
        recipe: $recipe
        pip: $pip
        npm: $npm
        cargo: $cargo
        stack: $stack
        go: $go
    }
}

export def merge [defs --os-type:string] {
    let d = $in
    {
        require: (resolve-def $defs $d.require --os-type $os_type)
        use: (resolve-def $defs $d.use --os-type $os_type)
    }
}
