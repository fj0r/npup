export def resolve-version [ctx] {
    let ver = $ctx.version
    let name = $ctx.name
    let fn = $ctx.filename?
    let url = $ctx.url | resolve-filename $name $ver
    let file = if ($fn | is-empty) {  $url | split row '/' | last } else { $fn }
    let file = $file | resolve-filename $name $ver
    let workdir = if ($ctx.workdir? | is-empty) { null } else {
        $ctx.workdir | resolve-filename $name $ver
    }
    $ctx | merge { url: $url, file: $file, workdir: $workdir }
}

def resolve-wrap [] {
    let ctx = $in
    let target = [$ctx.target $ctx.wrap?]
        | filter {|x| $x | not-empty }
        | path join
    $ctx | update target $target
}

def resolve-getter [ctx] {
    if ($ctx.cache | is-empty) {
        { url: $ctx.url local: false}
    } else {
        let f = [$ctx.cache $ctx.file] | path join
        let a = {
                url: $f
                local: false
            }
        if ($ctx.cache | find -r '^https?://' | is-empty) {
            $a | upsert local true
        } else { $a }
    }
}

def resolve-format [ctx] {
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
    mut override = false
    let target = if $fmt == 'zip' {
        $ctx.file
    } else if not ($fmt | str starts-with 'tar.') {
        $override = true
        let n = if ($ctx.filter? | is-empty) { $ctx.name } else { $ctx.filter | first }
        [$ctx.target $n] | path join
    } else {
        $ctx.target
    }
    {
        decmp: $decmp
        workdir: $ctx.workdir?
        target: $target
        strip: $ctx.strip?
        override: $override
    }
}

def resolve-filter [ctx] {
    mut rename = []
    mut lst = []
    let filters = if ($ctx.filter? | is-empty) { [] } else { $ctx.filter }
    for x in $filters {
        if ($x | describe -d | get type) == 'record' {
            let tf = $x.file | resolve-filename $ctx.name $ctx.version
            let nf = $x.rename | resolve-filename $ctx.name $ctx.version
            let trg = if ($ctx.workdir | is-empty) { $ctx.target } else { $ctx.workdir }
            $lst ++= [$tf]
            $rename ++= [[$'($trg)/($tf)', $'($ctx.target)/($nf)']]
        } else {
            let r = $x | resolve-filename $ctx.name $ctx.version
            $lst ++= [$r]
        }
    }
    {
        filter: $lst
        rename: $rename
    }
}

export def gen [ctx] {
    let target = $ctx.target?
    if ($ctx.url? | is-empty) {
        mkact log $ctx.name { event: "not found" }
    } else {
        let x = resolve-version $ctx | resolve-wrap

        let act = mkact 'download' $ctx.name {
            ...(resolve-getter $x)
            ...(resolve-format $x)
            ...(resolve-filter $x)
        }

        let md = if ($act.override or ($act.workdir? | not-empty)) {
            mkact 'dumb' null {}
        } else {
            mkact 'mkdir' $ctx.name { target: $act.target temp: false }
        }

        let mt = if ($act.workdir? | is-empty) { mkact 'dumb' null {} } else {
            mkact 'mkdir' $ctx.name { target: $act.workdir, temp: true }
        }

        [$md $mt $act]
    }
}
