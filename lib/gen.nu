def gen-git [$ctx] {
    mkact git $ctx.name {
        url: $ctx.url
        target: $ctx.target
        depth: 2
        log: true
    }
}

def gen-shell [it type] {
    let args = match $type {
            'shell' => $it.cmd
            'exec' => [($it.cmd | str join ' ')]
        }
    mkact 'shell' null {
        context: $it.name
        workdir: $it.workdir?
        runner: $it.runner?
        args: $args
    }
}

export def resolve [ctx name] {
    let vs = $ctx.data.versions
    let version = if $name in $vs { $vs | get $name } else { "" }
    let df = $ctx.defs | get $name
    let workdir = if ($df.workdir? | is-empty) { $df.workdir? } else {
        $df.workdir | resolve-filename $name $version
    }
    let install = $df.install?
    let install = if ($install | is-empty) { [] } else { $install }
    $install
    | each {|x|
        let r = $x | record-to-struct type data
        let d = if ($r.data? | is-empty) { {} } else { $r.data }
        {
            cache: $ctx.cache?
            target: $ctx.target?
            workdir: $workdir
        }
        | merge $d
        | merge {
            type: $r.type
            name: $name
            version: $version
        }
    }
}

def gen-recipe-env [ctx] {
    $ctx.args
    | reduce -f [] {|i, acc|
        let e = ($ctx.defs | get $i).env?
        if ($e | is-empty) { $acc } else {
            let es = $e
            | transpose k v
            | each {|x|
                if ($x.k | str starts-with '+') {
                    let n = $x.k | str substring 1..
                    mkact 'env-pre' $i { key: $n value: $x.v }
                } else {
                    mkact 'env' $i { key: $x.k value: $x.v }
                }
            }
            $acc | append $es
        }
    }
}

use download.nu
def gen-recipe [ctx] {
    $ctx.args
    | each {|i| resolve $ctx $i }
    | flatten
    | each {|i|
        match $i.type {
            download => {
                download gen $i
            }
            git => {
                gen-git $i
            }
            shell => {
                gen-shell $i 'shell'
            }
            exec => {
                gen-shell $i 'exec'
            }
        }
    }
    | flatten
}

def gen-cmd [ctx] {
    if $ctx.can_ignore and ($ctx.args | is-empty) {
        null
    } else if $ctx.act == 'recipe' {
        [
            ...(gen-recipe-env $ctx)
            ...(gen-recipe $ctx)
        ]
    } else {
        mkact 'common' $ctx.act { os: $ctx.os args: $ctx.args }
    }
}

export def stage [o clean default] {
    let setup = gen-cmd ($default | upsert act setup   | upsert can_ignore false)
    let instl = gen-cmd ($default | upsert act install | upsert args ($o.require.os? | append $o.use.os?))
    let recip = gen-cmd ($default | upsert act recipe  | upsert args $o.require.recipe?)
    let other = [pip npm cargo stack go]
    | each {|x| gen-cmd ($default | upsert act $x | upsert args ($o.require | get $x))}
    let final = if $clean {[
        (gen-cmd ($default | upsert act clean    | upsert args $o.use.os?))
        (gen-cmd ($default | upsert act teardown | upsert can_ignore false))
    ]} else {[]}
    [$setup $instl] | append $recip | append $other | append $final
}

export def optm [] {
    let x = $in
    mut o = []
    mut mkdir = []
    mut tempdir = []
    for i in $x {
        match $i.action {
            mkdir => {
                if ($i.temp? | default false) {
                    if not ($i.target in $tempdir) {
                        $tempdir ++= [$i.target]
                        $o ++= [$i]
                    } else {
                        let a = mkact log $i.context {
                            level: 'warn'
                            event: 'temp already exists'
                            target: $i.target
                        }
                        $o ++= [$a]
                    }

                } else {
                    if not ($i.target in $mkdir) {
                        $mkdir ++= [$i.target]
                        $o ++= [$i]
                    }
                }
            }
            dumb => {
                $o
            }
            _ => {
                $o ++= [$i]
            }
        }
    }
    for i in $tempdir {
        let a = mkact rm null {target: $i}
        $o ++= [$a]
    }
    $o
}
