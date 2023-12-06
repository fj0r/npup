export def resolve [ctx] {
    let ver = $ctx.version
    let name = $ctx.name
    let fn = $ctx.filename?
    let url = $ctx.url | resolve-filename $name $ver
    let file = if ($fn | is-empty) {  $url | split row '/' | last } else { $fn }
    let file = $file | resolve-filename $name $ver
    let workdir = if ($ctx.workdir? | is-empty) { null } else {
        $ctx.workdir | resolve-filename $name $ver
    }
    { url: $url, file: $file, workdir: $workdir }
}

def resolve-download-getter [ctx x cache] {
    if ($cache | is-empty) {
        mkact 'download' $ctx.name { url: $x.url target: $x.file}
    } else {
        let f = [$cache $x.file] | path join
        let a = mkact 'download' $ctx.name {
                url: $f
                target: $x.file
            }
        if ($cache | find -r '^https?://' | is-empty) {
            $a | upsert cache true
        } else { $a }
    }
}

def resolve-tar-filter [workdir filter target name version] {
    if ($filter | is-empty) { [] } else {
        $filter
        | each {|x|
            if ($x | describe -d | get type) == 'record' {
                let tf = $x.file | resolve-filename $name $version
                let fn = $tf | split row '/' | last
                let nf = $x.rename | resolve-filename $name $version
                let trg = if ($workdir | is-empty) { $target } else { $workdir }
                [$tf $'($trg)/($fn)' $'($target)/($nf)']
            } else {
                let r = $x | resolve-filename $name $version
                [$r]
            }
        }
    }
}

def resolve-zip-filter [workdir filter target name version strip] {
    let nl = (char newline)
    let strip = if ($strip | is-empty) { 0 } else { $strip }
    if ($filter | is-empty) {
        [mkact mv null { from: $"${temp_dir}/*" to: $target }]
    } else {
        $filter
        | each {|x|
            if ($x | describe -d | get type) == 'record' {
                mkact mv null {from: $"${temp_dir}/($x.file)" to: $"($target)/($x.rename)"}

            } else {
                let f = $x | resolve-filename $name $version
                let t = $f | split row '/' | range $strip.. | str join '/'
                mkact mv null {from: $"($workdir)/($f)" to: $"($target)/($t)" }
            }
        }
    }
}

def resolve-unzip [getter ctx] {
    let trg = [$ctx.target $ctx.wrap?]
        | filter {|x| $x | not-empty }
        | path join
    let fmt = if ($ctx.format? | not-empty ) { $ctx.format } else {
        let fn = $ctx.file | split row '.'
        let zf = $fn | last
        if ($fn | range (-2..-2) | get 0) == 'tar' {
            $"tar.($zf)"
        } else {
            $zf
        }
    }
    let decmp = match $fmt {
        'tar.gz'  => $"tar zxf"
        'tar.zst' => $"zstd -d -T0 | tar xf"
        'tar.bz2' => $"tar jxf"
        'tar.xz'  => $"tar Jxf"
        'gz'      => $"gzip -d"
        'zst'     => $"zstd -d"
        'bz2'     => $"bzip2 -d"
        'xz'      => $"xz -d"
        'zip'     => $"unzip"
        _ => "(!unknown format)"
    }

    let md = mkact 'mkdir' $ctx.name { target: $trg temp: false }
    let mt = if ($ctx.workdir? | is-empty) { mkact 'dumb' null {} } else {
        mkact 'mkdir' $ctx.name { target: $ctx.workdir temp: true }
    }
    if ($fmt | str starts-with 'tar.') {
        let f = (resolve-tar-filter $ctx.workdir $ctx.filter? $trg $ctx.name $ctx.version?)
            | reduce -f {fs: [], mv: []} {|x, acc|
                let acc = if ($x.0? | is-empty) { $acc } else {
                    $acc | update fs ($acc.fs | append $x.0?)
                }
                let acc = if ($x.1? | is-empty) { $acc } else {
                    $acc | update mv ($acc.mv | append (mkact mv null {from: $x.1 to: $x.2}))
                }
                $acc
            }
        let u = $getter | merge {
            decompress: $decmp
            target: $trg
            strip: $ctx.strip?
            filter: $f.fs
            workdir: $ctx.workdir?
        }
        [$md $mt $u] | append $f.mv
    } else if $fmt == 'zip' {
        if ($ctx.workdir? | is-empty) {
            mkact log $ctx.workdir { event: "workdir should not empty" }
        }
        let f = (resolve-zip-filter $ctx.workdir $ctx.filter? $trg $ctx.name $ctx.version? $ctx.strip?)
        let u = $getter | merge {
            decompress: $decmp
            target: $ctx.file
            workdir: $ctx.workdir
        }
        [$md $mt $u] | append $f
    } else {
        let n = if ($ctx.filter? | is-empty) { $ctx.name } else { $ctx.filter | first }
        let t = [$trg $n] | path join
        let u = $getter | merge {
            decompress: $decmp
            target: $t
            redirect: true
        }
        [$md $mt $u]
    }
}

export def gen [ctx] {
    let cache = $ctx.cache?
    let target = $ctx.target?
    if ($ctx.url? | is-empty) {
        mkact log $ctx.name { event: "not found" }
    } else {
        let x = resolve $ctx
        let f = resolve-download-getter $ctx $x $cache
        let cx = $ctx | merge {
            file: $x.file
            cache: $cache
            target: $target
            workdir: $x.workdir
        }
        let r = resolve-unzip $f $cx
        $r
    }
}

