use ./lib/utils.nu *
use ./lib/os.nu
use ./lib/deps.nu
use ./lib/gen.nu
use ./lib/interpret.nu
use ./lib/extractor.nu


def setup [
    defs
    data
    --os-type:  string
    --target:   string
    --cache:    string
    --dry-run:  bool
    --clean:    bool
] {
    gen stage $in $clean {
        os: $os_type
        dry_run: $dry_run
        defs: $defs
        data: $data
        target: $target
        cache: $cache
        can_ignore: true
        act: null
        args: null
    }
    | gen optm
    | interpret $dry_run
}

def run [
    req
    pkgs
    defs
    data
    --os-type:  string
    --target:   string
    --cache:    string
    --dry-run:  bool
    --clean:    bool
] {
    $pkgs
    | deps sort $req
    | deps resolve
    | deps merge $defs --os-type $os_type
    | (setup $defs $data
        --os-type $os_type
        --target $target
        --dry-run $dry_run
        --clean $clean
        --cache $cache
    )
}

def update-version [manifest] {
    mut data = {}
    for item in ($manifest | transpose k v) {
        let i = $item.v?
        print $'==> ($item.k)'
        let url = $i.version?.url?
        let ext = $i.version?.extract?
        let header = $i.version?.header?
        let header = if ($header | is-empty) { [] } else {
            $header | transpose k v | each {|x| [-H $"($x.k): ($x.v)"] } | flatten
        }
        if ($url | not-empty) {
            let ver = (extractors run (curl -sSL $header $url) $ext)
            print $ver
            $data = ($data | upsert $item.k $ver)
        }
    }
    $data
}

def download-recipe [defs versions --cache:string] {
    mkdir /tmp/npup
    let ctx = {
        defs: $defs
        data: { versions: $versions }
        cache: $cache
    }
    for y in ($defs | columns | each {|x| resolve-recipe $ctx $x }) {
        for i in $y {
            if $i.type == 'download' {
                if ($i.url? | is-empty) {
                    print $'# ($i.name)'
                } else {
                    let x = resolve-download-filename $i
                    print $'# download ($x.file)'
                    let t = [$cache $x.file] | filter {|x| $x | not-empty } | path join
                    if ($cache | find -r '^https?://' | is-empty) {
                        wget -c ($x.url) -O ($t)
                    } else {
                        let lt = ['/tmp/npup' $x.file] | path join
                        wget -c ($x.url) -O ($lt)
                        curl -T ($lt) ($t)
                    }
                }
            }
        }
    }
    rm -rf /tmp/npup
}

export def main [
    --dry-run
    --clean
    --cache: string
    --target: string = '/usr/local'
    ...args:string@compos
] {
    print $"#===> $env.DEBUG = ($env.DEBUG?)"
    let act = $args.0
    let req = $args | range 1.. | prepend default
    let manifest = open $"($env.FILE_PWD)/manifest.yml"
    let data = open $"($env.FILE_PWD)/data.yml"
    let ostype = (os type)
    match $act {
        setup => {
            (run $req
                $manifest.pkgs $manifest.defs $data
                --os-type $ostype
                --target $target
                --dry-run $dry_run
                --clean $clean
                --cache $cache
            )
        }
        gensh => {
            let ostype = if ($args.1? | is-empty) { $ostype } else { $args.1 }
            (run $req
                $manifest.pkgs $manifest.defs $data
                --os-type $ostype
                --target $target
                --dry-run true
                --clean $clean
                --cache $cache
            )
        }
        update => {
            let x = (update-version $manifest.defs)
            $data
            | upsert versions ($data.versions | merge $x)
            | to yaml
            | save -f $"($env.FILE_PWD)/data.yml"
        }
        download => {
            download-recipe $manifest.defs $data.versions --cache $cache
        }
        debug => {
            $manifest.pkgs
                | deps sort $req                                | log 'deps sort'
                | deps resolve                                  | log 'deps resolve'
                | deps merge $manifest.defs --os-type $ostype   | log 'deps merge'
        }
        _ => {
            echo $manifest | to json
        }

    }
}

def compos [context: string, offset: int] {
    let pkgs = open $"($env.PWD)/manifest.yml" | get pkgs | get name
    [$context $offset] | completion-generator from tree [
        { value: gensh, description: 'gen sh -c', next: (
            [debian arch alpine redhat] | each {|x| { value: $x, next: $pkgs } }
        ) }
        { value: build, description: 'Dockerfile' }
        { value: update, description: 'versions' }
        { value: download, description: 'assets' }
    ]
}
